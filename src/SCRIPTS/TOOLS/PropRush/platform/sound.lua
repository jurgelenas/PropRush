-- Sound and haptics. Event cues play in the tone queue (melodies) or the PLAY_NOW slot (single short hits); the motor
-- is a tone on the background slot, re-sent every frame before it ends, so it never touches the queue. Every
-- argument to playTone/playHaptic must be an integer: a fraction is a Lua error on the radio.

local settings, list = ...

local floor, random, byte, char = math.floor, math.random, string.byte, string.char

-- Cues (platform/cues) packed into CUES, one after another: notes, rank, channel, haptic length, pause and
-- repeats, then per note 6 bytes: frequency high and low byte, length and pause in 10 ms, slide + 128, volume.
-- AT holds each cue's offset into CUES as a high and a low byte. The list itself is let go.
local CUES, AT = "", ""
for id = 1, #list do
  local c = list[id]
  AT = AT .. char(#CUES // 256, #CUES % 256)
  -- rank, channel, haptic length, pause, repeats
  local s = char((#c - 5) // 5, c[1], c[2], c[3], c[4], c[5])
  for i = 6, #c, 5 do
    -- frequency, length, pause, slide, volume
    local f = c[i]
    s = s .. char(f // 256, f % 256, c[i + 1] // 10, c[i + 2] // 10, c[i + 3] + 128, c[i + 4])
  end
  CUES = CUES .. s
end
list = nil
-- Cue numbers used here (platform/cues)
local CUE_REV, CUE_ARMED, CUE_BUMP, CUE_STRIKE, CUE_STRIKE_HARD, CUE_CRACKLE, CUE_CRACKLE_LOUD, CUE_CHIME, CUE_GATE =
  2, 4, 7, 8, 9, 10, 11, 32, 38

-- Added to the chime for combo multipliers 1..5: E6, F#6, G#6, A6, C#7
local CHIME = { 0, 161, 342, 441, 898 }
-- Longest a cue of each rank may wait behind the queue (10 ms ticks) before it is dropped: late is worse than none
local MAX_LAG = { 60, 60, 30, 15, 0 }
-- Ticks between haptics, bar urgent ones (rank 2, hits)
local HAPTIC_GAP = 20
local HIT_GAP = 15
-- Motor: throttle floor (airmode idle), spool-up and wind-down rates (per second), pitch at 0 and full rpm (idle
-- ~420 Hz, hover ~580, full ~900), and the tone length, longer than the longest frame so it never gaps between
-- re-sends. The pitch alternates by WOBBLE every frame for a rough buzz rather than a whistle, by STRIKE_WOBBLE
-- during a prop strike.
local IDLE, SPOOL, WIND_DOWN = 0.04, 12, 3
local F_LO, F_SPAN = 300, 600
local WOBBLE, STRIKE_WOBBLE = 0.05, 0.2
local MOTOR_TONE, MOTOR_VOLUME = 160, 1
-- rpm from sqrt(throttle) times cell voltage over a full 4.2 V
local VOLT_RPM = 1 / 4.2

-- Ticks (10 ms) at which the queue and the PLAY_NOW slot run dry, as far as this module sent them
local qEnd, pEnd, hEnd, hitEnd = 0, 0, 0, 0
local rpm, mF, odd = 0, 0, false

local Sound = {}

local function haptic(d, p, rep, urgent, now)
  if settings.haptic and (urgent or now >= hEnd) then
    playHaptic(d, p, urgent and PLAY_NOW + rep or rep)
    hEnd = now + HAPTIC_GAP
  end
end

-- Cue id; add: Hz added to every note; rep: extra plays of the first note; force: skips the lag check (the second
-- half of a pair). True when it played.
local function play(id, add, rep, force)
  local hi, lo = byte(AT, 2 * id - 1, 2 * id)
  local p = hi * 256 + lo + 1
  local n, rank, channel, hLen, hPause, hRep = byte(CUES, p, p + 5)
  local now = getTime()
  if hLen > 0 then
    haptic(hLen, hPause, hRep, rank <= 2, now)
  end
  if settings.sound == 0 then
    return false
  end
  local flags = 0
  if channel == 1 and now >= pEnd and n == 1 then
    flags = PLAY_NOW
  else
    if qEnd < now then
      qEnd = now
    end
    if not force and qEnd - now > MAX_LAG[rank] then
      return false
    end
  end
  add, rep = add or 0, rep or 0
  for i = p + 6, p + 6 * n, 6 do
    local fHi, fLo, d, ps, slide, volume = byte(CUES, i, i + 5)
    d, ps = d * 10, ps * 10
    playTone(floor(fHi * 256 + fLo + add), d, ps, flags + rep, slide - 128, volume)
    local t = (d + ps) * (rep + 1) // 10
    if flags == 0 then
      qEnd = qEnd + t
    else
      pEnd = now + t + 1
    end
    rep = 0
  end
  return true
end

-- Cue id (platform/cues), rep extra plays of its first note
function Sound.cue(id, rep)
  play(id, 0, rep)
end

-- Trick cue id of n turns (ticks) at combo multiplier mult
function Sound.trick(id, n, mult)
  n = n or 1
  if play(id, 0, n > 8 and 7 or n - 1) then
    play(CUE_CHIME, CHIME[mult], 0, true)
  end
end

-- A hold trick's tick cue id at its k-th half second (0 when it qualifies): the tick climbs
function Sound.tick(id, k)
  play(id, 60 * k)
end

-- Gate k of n (not the start): the blip climbs a fourth through the lap
function Sound.gate(k, n)
  play(CUE_GATE, 441 * (k - 2) // (n > 3 and n - 2 or 1))
end

-- Contacts this frame: hit, the speed into a surface; struck, the edge-on speed of a prop strike (0 none)
function Sound.contact(hit, struck)
  local now = getTime()
  if now < hitEnd then
    return
  end
  if struck > 0 then
    hitEnd = now + HIT_GAP
    haptic(6 + floor(struck < 6 and struck or 6), 0, 0, true, now)
    play(struck < 3 and CUE_STRIKE or CUE_STRIKE_HARD)
  elseif hit >= 1.5 then
    hitEnd = now + HIT_GAP
    if hit > 3 then
      haptic(6, 0, 0, true, now)
    end
    play(CUE_BUMP)
  end
end

-- Static ticks as dense as the picture's snow (loss 0..1)
function Sound.crackle(loss)
  if loss > 0.05 and random() < loss then
    play(loss < 0.5 and CUE_CRACKLE or CUE_CRACKLE_LOUD, random(0, 1600))
  end
end

-- Everything stops: queue, motor (the tone already playing finishes)
function Sound.stop()
  flushAudio()
  rpm, mF, qEnd = 0, 0, 0
end

-- The impact, then the motors winding down from the pitch they had (not when the battery had already stopped them)
function Sound.crash(dead)
  local now = getTime()
  local f = mF
  Sound.stop()
  haptic(25, 0, 0, true, now)
  if settings.sound == 0 then
    return
  end
  if now >= pEnd then
    playTone(2000, 30, 0, PLAY_NOW, -60, 5)
    pEnd = now + 4
  end
  if not dead and f > 0 then
    local d = (f - 250) // 20 * 10
    d = d < 150 and 150 or (d > 500 and 500 or d)
    playTone(f, d, 100, 0, -2, 2)
    qEnd = now + (d + 100) // 10
  end
end

-- Once per frame of flight, with the frame's dt: pitch follows rpm, which follows the throttle and the battery
-- voltage; disarmed or with the battery dead the motors wind down
function Sound.motor(q, dt)
  if settings.sound ~= 2 then
    return
  end
  local dead = q.dead or not q.armed
  local t = q.throttle
  local target = dead and 0 or math.sqrt(t < IDLE and IDLE or t) * q.voltage * VOLT_RPM
  local k = dt * (dead and WIND_DOWN or SPOOL)
  rpm = rpm + (target - rpm) * (k > 1 and 1 or k)
  if dead and rpm < 0.12 then
    if mF > 0 then
      playTone(F_LO, 0, 0, PLAY_BACKGROUND + PLAY_NOW)
      mF = 0
    end
    return
  end
  local w = q.strike > 0 and STRIKE_WOBBLE or WOBBLE
  odd = not odd
  local f = floor((F_LO + F_SPAN * rpm) * (odd and 1 - w or 1 + w))
  playTone(f, MOTOR_TONE, 0, PLAY_BACKGROUND + PLAY_NOW, 0, MOTOR_VOLUME)
  mF = f
end

-- A setting just changed: let it be heard or felt
function Sound.preview(key)
  if key == "sound" then
    play(settings.sound == 2 and CUE_REV or CUE_ARMED)
  elseif key == "haptic" and settings.haptic then
    haptic(8, 0, 0, true, getTime())
  end
end

return Sound
