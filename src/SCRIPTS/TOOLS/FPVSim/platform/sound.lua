-- Sound and haptics. Event cues play in the tone queue (melodies) or the PLAY_NOW slot (single short hits); the motor
-- is a tone on the background slot, re-sent every frame before it ends, so it never touches the queue. Every
-- argument to playTone/playHaptic must be an integer: a fraction is a Lua error on the radio.

local settings = ...

local floor, random, gmatch = math.floor, math.random, string.gmatch

-- A cue: rank (2 most important .. 5 ambience), channel (0 queue, 1 PLAY_NOW), haptic length (10 ms units, 0 none,
-- under 6 underflows with the radio's haptic length at -2), haptic pause (5 ms units) and repeats; then notes of
-- frequency (Hz), length and pause (ms, multiples of 10), slide (Hz per ms) and volume (1..5). Event notes are in
-- A major from 880 Hz up, above the motor; success rises, failure falls, warnings repeat one note.
local CUES = {
  deny = "4 0 0 0 0 698 60 20 0 3 659 100 0 0 3",
  rev = "3 0 0 0 0 420 480 0 1 1",
  throttle = "4 0 0 0 0 1319 60 60 0 3 1319 60 0 0 3",
  armed = "3 0 6 0 0 880 60 20 0 3 1109 60 20 0 3 1319 100 0 0 3",
  respawn = "3 1 0 0 0 660 60 0 10 2",
  bump = "5 1 0 0 0 520 40 0 -8 2",
  strike = "3 1 0 0 0 1600 30 0 -40 3",
  strikeHard = "3 1 0 0 0 1600 30 0 -40 4",
  crackle = "5 1 0 0 0 2000 10 0 0 1",
  crackleLoud = "5 1 0 0 0 2000 10 0 0 2",
  low = "4 0 6 20 1 1760 50 50 0 3",
  empty = "2 0 15 20 1 880 120 30 0 4 659 120 30 0 4 440 250 0 -1 4",
  range = "4 0 0 0 0 1480 80 40 0 3 1109 120 0 0 3",
  link = "4 0 0 0 0 1109 60 20 0 2 1480 80 0 0 2",
  -- Tricks: a motif per kind (its first note repeated once per turn), then the combo chime
  roll = "3 0 0 0 0 1109 30 20 0 3",
  flip = "3 0 0 0 0 988 30 20 0 3",
  flipRoll = "3 0 0 0 0 988 30 20 0 3 1109 30 20 0 3",
  yaw = "3 0 0 0 0 1319 30 20 5 3",
  trippy = "3 0 0 0 0 1319 30 20 -5 3 2637 40 0 0 3",
  loop = "3 0 0 0 0 880 120 0 8 3 1760 60 10 -8 3",
  splitS = "3 0 0 0 0 1760 120 0 -8 3 880 60 20 8 3",
  dive = "3 0 0 0 0 1760 200 20 -5 3",
  gap = "3 0 0 0 0 1109 80 0 12 3",
  gapInverted = "3 0 0 0 0 1109 80 0 12 3 2637 40 0 0 3",
  hang = "3 0 0 0 0 988 140 20 0 3",
  knife = "3 0 0 0 0 1175 140 20 0 3",
  proxy = "3 0 0 0 0 1480 140 20 0 3",
  hangTick = "5 1 0 0 0 988 20 0 0 2",
  knifeTick = "5 1 0 0 0 1175 20 0 0 2",
  proxyTick = "5 1 0 0 0 1480 20 0 0 2",
  chime = "3 0 0 0 0 1319 90 0 0 4",
  bank = "3 0 0 0 0 1760 50 10 0 4 2217 50 10 0 4 2637 120 0 0 4",
  lost = "2 0 0 0 0 740 80 20 0 4 698 80 20 0 4 659 180 0 -1 4",
  record = "2 0 0 0 0 1760 60 10 0 4 2217 60 10 0 4 2637 150 0 0 4",
  best = "2 0 8 20 2 880 70 10 0 5 1109 70 10 0 5 1319 70 10 0 5 1760 70 60 0 5 1319 70 10 0 5 1760 250 0 0 5",
  -- Racing
  start = "3 0 8 0 0 1760 250 0 0 4",
  gate = "3 1 0 0 0 1319 40 0 0 3",
  lap = "2 0 6 0 0 1319 60 20 0 4 1760 140 0 0 4",
  bestLap = "2 0 8 20 1 1319 60 10 0 5 1760 60 10 0 5 2217 60 10 0 5 2637 200 0 0 5",
}

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
local buf = {}

local Sound = {}

local function haptic(d, p, rep, urgent, now)
  if settings.haptic and (urgent or now >= hEnd) then
    playHaptic(d, p, urgent and PLAY_NOW + rep or rep)
    hEnd = now + HAPTIC_GAP
  end
end

-- add: Hz added to every note; rep: extra plays of the first note; force: skips the lag check (the second half of
-- a pair). True when it played.
local function play(name, add, rep, force)
  local n = 0
  for v in gmatch(CUES[name], "%-?%d+") do
    n = n + 1
    buf[n] = tonumber(v)
  end
  local now = getTime()
  local rank = buf[1]
  if buf[3] > 0 then
    haptic(buf[3], buf[4], buf[5], rank <= 2, now)
  end
  if settings.sound == 0 then
    return false
  end
  local flags = 0
  if buf[2] == 1 and now >= pEnd and n == 10 then
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
  for i = 6, n, 5 do
    local d, p = buf[i + 1], buf[i + 2]
    playTone(floor(buf[i] + add), d, p, flags + rep, buf[i + 3], buf[i + 4])
    local t = (d + p) * (rep + 1) // 10
    if flags == 0 then
      qEnd = qEnd + t
    else
      pEnd = now + t + 1
    end
    rep = 0
  end
  return true
end

function Sound.cue(name, rep)
  play(name, 0, rep)
end

-- A trick of n turns (ticks) at combo multiplier mult
function Sound.trick(name, n, mult)
  n = n or 1
  if play(name, 0, n > 8 and 7 or n - 1) then
    play("chime", CHIME[mult], 0, true)
  end
end

-- A hold trick's k-th half second (0 when it qualifies): the tick climbs
function Sound.tick(name, k)
  play(name, 60 * k)
end

-- Gate k of n (not the start): the blip climbs a fourth through the lap
function Sound.gate(k, n)
  play("gate", 441 * (k - 2) // (n > 3 and n - 2 or 1))
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
    play(struck < 3 and "strike" or "strikeHard")
  elseif hit >= 1.5 then
    hitEnd = now + HIT_GAP
    if hit > 3 then
      haptic(6, 0, 0, true, now)
    end
    play("bump")
  end
end

-- Static ticks as dense as the picture's snow (loss 0..1)
function Sound.crackle(loss)
  if loss > 0.05 and random() < loss then
    play(loss < 0.5 and "crackle" or "crackleLoud", random(0, 1600))
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
-- voltage
function Sound.motor(q, dt)
  if settings.sound ~= 2 then
    return
  end
  local dead = q.dead
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
    play(settings.sound == 2 and "rev" or "armed")
  elseif key == "haptic" and settings.haptic then
    haptic(8, 0, 0, true, getTime())
  end
end

return Sound
