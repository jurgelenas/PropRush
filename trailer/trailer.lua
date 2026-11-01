-- Trailer footage: scripted flights through the maps, drawn on the host as the radio draws them, saved as PNG frames
-- in the plain LCD look (128 x 64) for trailer/trailer.sh to scale and cut. Usage, from the repo root:
--   edgetx-cli dev simulator --radio "RadioMaster Boxer" --headless --script trailer/trailer.lua
-- OUT=dir (default /tmp/proprush-trailer, must exist), SHOT=pattern renders only the shots it matches (a Lua pattern on the whole name).
--
-- A shot's path runs through keys {t, x, y, z} (seconds, metres) as a time-parametrised Hermite spline, or comes from
-- pos(t). The quad's attitude follows from the path as a quad's would: its up axis along the thrust that drives the
-- motion against gravity and drag, its nose along the velocity. spins add flips and rolls on top.

local H = dofile("test/harness.lua")
H.install(128, 64)
assert(H.loadFonts(), "No EdgeTX fonts found: the trailer needs its text")

local OUT = (os.getenv("OUT") or "/tmp/proprush-trailer") .. "/"
-- SHOT: a Lua pattern for the shots to render, matched against the whole name
local ONLY = os.getenv("SHOT")
local DEBUG = os.getenv("DEBUG")

local sqrt, sin, cos, asin, pi = math.sqrt, math.sin, math.cos, math.asin, math.pi
local RAD = pi / 180

local FPS, SUB = 30, 2
local DT = 1 / (FPS * SUB)
-- As physics/quad's
local G, DRAG = 9.81, 0.04

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/PropRush/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("gfx/render3d")
local Quad = load("physics/quad", load("physics/rates"))
local Ground, Scene, Gap = load("world/ground", R), load("world/scene", R), load("world/gap")
local settings = load("config/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)
R.setView(0, 0, LCD_W, LCD_H, settings.fov, settings.camAngle)
local highscore = { byMap = {}, record = function() end }

local function newMap(mode, id)
  return load("maps/" .. mode .. "/" .. id, Ground, Scene, Gap, R, load)
end

-- Scene object whose slot count is n and that carries a draw method: the map's moving thing
local function findObject(Map, n)
  for _, o in ipairs(Map.scene.objects) do
    if #o == n and o.draw then
      return o
    end
  end
end

-- Natural cubic spline through keys {t, x, y, z}: acceleration, and with it the quad's attitude, runs on smoothly
-- through every key. Beyond the ends it carries on straight at the end velocity.
local function splineCoefficients(keys)
  local n, M = #keys, {}
  for k = 2, 4 do
    local m, c, d = {}, {}, {}
    m[1], m[n] = 0, 0
    -- Tridiagonal system for the second derivatives at the inner keys (Thomas algorithm)
    for i = 2, n - 1 do
      local h0, h1 = keys[i][1] - keys[i - 1][1], keys[i + 1][1] - keys[i][1]
      local a, b, cc = h0, 2 * (h0 + h1), h1
      local r = 6 * ((keys[i + 1][k] - keys[i][k]) / h1 - (keys[i][k] - keys[i - 1][k]) / h0)
      if i > 2 then
        b, r = b - a * c[i - 1], r - a * d[i - 1]
      end
      c[i], d[i] = cc / b, r / b
    end
    for i = n - 1, 2, -1 do
      m[i] = d[i] - c[i] * (m[i + 1] or 0)
    end
    M[k] = m
  end
  return M
end

local function spline(keys, t)
  local M = keys.M
  if not M then
    M = splineCoefficients(keys)
    keys.M = M
  end
  local n = #keys
  local i = 1
  while i < n - 1 and t > keys[i + 1][1] do
    i = i + 1
  end
  local k0, k1 = keys[i], keys[i + 1]
  local h = k1[1] - k0[1]
  local out = {}
  for k = 2, 4 do
    local m0, m1 = M[k][i], M[k][i + 1]
    if t < k0[1] and i == 1 then
      local slope = (k1[k] - k0[k]) / h - h * (2 * m0 + m1) / 6
      out[k - 1] = k0[k] + slope * (t - k0[1])
    elseif t > k1[1] then
      local slope = (k1[k] - k0[k]) / h + h * (m0 + 2 * m1) / 6
      out[k - 1] = k1[k] + slope * (t - k1[1])
    else
      local A, B = (k1[1] - t) / h, (t - k0[1]) / h
      out[k - 1] = A * k0[k] + B * k1[k] + ((A * A * A - A) * m0 + (B * B * B - B) * m1) * h * h / 6
    end
  end
  return out[1], out[2], out[3]
end

local function norm(x, y, z)
  local l = sqrt(x * x + y * y + z * z)
  if l < 1e-9 then
    return 0, 0, 0, 0
  end
  return x / l, y / l, z / l, l
end

local function smooth(u)
  u = u < 0 and 0 or u > 1 and 1 or u
  return u * u * (3 - 2 * u)
end

-- Attitude from the path at t: up along the thrust, nose along the velocity (else the last nose) square to it, or
-- towards aim x, y, z when given
local function attitude(pos, t, pf, pu, tx, ty, tz, tw)
  local e = 1 / 120
  local x0, y0, z0 = pos(t - e)
  local x1, y1, z1 = pos(t)
  local x2, y2, z2 = pos(t + e)
  local vx, vy, vz = (x2 - x0) / (2 * e), (y2 - y0) / (2 * e), (z2 - z0) / (2 * e)
  local ax, ay, az = (x2 - 2 * x1 + x0) / (e * e), (y2 - 2 * y1 + y0) / (e * e), (z2 - 2 * z1 + z0) / (e * e)
  local s = sqrt(vx * vx + vy * vy + vz * vz)
  -- Where the thrust nearly vanishes (over the top of a loop) the up axis holds rather than flipping
  local ux, uy, uz =
    norm(ax + DRAG * s * vx + 2 * pu[1], ay + G + DRAG * s * vy + 2 * pu[2], az + DRAG * s * vz + 2 * pu[3])
  local hx, hy, hz = vx + 2 * pf[1], vy + 2 * pf[2], vz + 2 * pf[3]
  if tx then
    local w = tw or 1
    local ax2, ay2, az2 = norm(tx - x1, ty - y1, tz - z1)
    local bx, by, bz = norm(hx, hy, hz)
    hx, hy, hz = bx + w * (ax2 - bx), by + w * (ay2 - by), bz + w * (az2 - bz)
  end
  local d = hx * ux + hy * uy + hz * uz
  local fx, fy, fz, l = norm(hx - d * ux, hy - d * uy, hz - d * uz)
  if l < 1e-6 then
    fx, fy, fz = pf[1], pf[2], pf[3]
  end
  -- r = u x f
  local rx, ry, rz = uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
  return x1, y1, z1, vx, vy, vz, rx, ry, rz, ux, uy, uz, fx, fy, fz
end

-- Rotates axis a about unit axis k by angle th (Rodrigues)
local function about(ax, ay, az, kx, ky, kz, th)
  local c, s = cos(th), sin(th)
  local d = (kx * ax + ky * ay + kz * az) * (1 - c)
  return ax * c + (ky * az - kz * ay) * s + kx * d,
    ay * c + (kz * ax - kx * az) * s + ky * d,
    az * c + (kx * ay - ky * ax) * s + kz * d
end

local function dot(ax, ay, az, bx, by, bz)
  return ax * bx + ay * by + az * bz
end

-- Turns the quad onto r, u, f through Quad:rotate, so freestyle reads its flips and rolls, then sets them exactly
local function turnTo(q, rx, ry, rz, ux, uy, uz, fx, fy, fz)
  local function as(v)
    return asin(v < -1 and -1 or v > 1 and 1 or v)
  end
  q:rotate(
    as(dot(fx, fy, fz, q.ux, q.uy, q.uz)),
    as(dot(fx, fy, fz, q.rx, q.ry, q.rz)),
    -as(dot(rx, ry, rz, q.ux, q.uy, q.uz))
  )
  q.rx, q.ry, q.rz, q.ux, q.uy, q.uz, q.fx, q.fy, q.fz = rx, ry, rz, ux, uy, uz, fx, fy, fz
end

-- Seconds the camera takes to ease most of the way onto a new attitude
local EASE = 0.25
local SPIN_FADE = 0.3

-- Nose-down degrees at t from keys {t, degrees}, eased between them: a pilot pitching over to look down
local function tiltAt(keys, t)
  if t <= keys[1][1] then
    return keys[1][2]
  end
  for i = 2, #keys do
    if t <= keys[i][1] then
      local a, b = keys[i - 1], keys[i]
      return a[2] + (b[2] - a[2]) * smooth((t - a[1]) / (b[1] - a[1]))
    end
  end
  return keys[#keys][2]
end

local SHOTS = {}
local function shot(s)
  SHOTS[#SHOTS + 1] = s
end

-- Title cards: lines of {text, big}, centred
local function card(name, lines, duration)
  shot({ name = name, card = lines, duration = duration or 2 })
end
card("title", { { "PROPRUSH", true }, { "" }, { "An FPV simulator" }, { "on your EdgeTX radio" } }, 2.5)
card("racing", { { "RACING", true }, { "" }, { "10 gate tracks" }, { "against the clock" } })
card("freestyle", { { "FREESTYLE", true }, { "" }, { "10 maps. Flips, rolls," }, { "gaps, dives and combos" } })
card("end", { { "PROPRUSH", true }, { "" }, { "EdgeTX 2.12.4+" }, { "B&W radios" }, { "Free and open source" } }, 3.5)

-- The menu: the intro skipped, the cursor down to FREESTYLE and back, into RACING's map list
shot({
  name = "menu",
  menu = { 0.6, EVT_VIRTUAL_NEXT, 1.2, EVT_VIRTUAL_PREV, 1.8, EVT_VIRTUAL_ENTER },
  duration = 2.6,
})

-- SUPER 8: into the cube, round the north-east loop through two gates and back west through the cube
shot({
  name = "super8",
  mode = "racing",
  map = "super8",
  voltage = 4.1,
  speed = 15,
  keys = {
    { 0, 2.5, -32 },
    { 0, 3.3, -14 },
    { 0, 3.5, 0 },
    { 0.5, 3.4, 9 },
    { 4, 3, 26 },
    { 10, 2.5, 39 },
    { 20, 2.2, 45 },
    { 33, 3, 42 },
    { 42, 4.8, 32 },
    { 45, 5.7, 20 },
    { 41, 5.2, 7 },
    { 26, 4, 0.5 },
    { 0, 3.5, 0 },
    { -14, 3, -3 },
  },
})

-- DRIFT: chasing the car up the start straight and round the sweeper, behind and above it
shot({
  name = "drift",
  mode = "freestyle",
  map = "drift",
  voltage = 3.95,
  record = function(Map, last)
    local car = findObject(Map, 17)
    local h = car[16]
    -- Unwrapped across the lap line
    if last then
      h = h + 2 * pi * math.floor((last[3] - h) / (2 * pi) + 0.5)
    end
    return { car[12], car[13], h }
  end,
  -- The car's line smoothed over ~0.5 s either way: the quad follows its line, not every lift of the throttle
  sigma = 0.5,
  pos = function(t, rec)
    local x, z, h = rec(t)
    return x - 11 * sin(h) + 1.5 * cos(h), 3.8, z - 11 * cos(h) - 1.5 * sin(h)
  end,
  -- The camera held on the car
  aim = function(t, rec)
    local x, z = rec(t)
    return x, 0.6, z
  end,
  aimPitch = true,
  level = 0.6,
  cam = 20,
  lead = 1.2,
  duration = 4.2,
})

-- TRAINYARD: low through the signal gantry, under the platform canopy between its posts, then out and up over the
-- train (its rear at x -35 at the map's start, running east at 8 m/s on z 30)
shot({
  name = "trainyard",
  mode = "freestyle",
  map = "trainyard",
  voltage = 3.9,
  lead = 0.5,
  keys = {
    { -0.5, -82, 4.5, 17 },
    { 0.5, -64, 3, 17 },
    { 1.2, -51, 2.6, 17 },
    { 2.1, -34, 2.6, 17 },
    { 3.0, -18, 2.6, 17 },
    { 3.8, -3, 3.6, 18.5 },
    { 4.7, 12, 6, 23 },
  },
  level = 0.85,
  wobble = 1,
  duration = 4.5,
})

-- CITY OPEN: up the avenue past the arch block, under the skybridge, then a climb past the spire that lifts over
-- the rooftops into the skyline
shot({
  name = "cityopen",
  mode = "freestyle",
  map = "city",
  voltage = 3.85,
  speed = 20,
  keys = {
    { 6, 18, -15 },
    { 4, 18, 10 },
    { -3, 20, 35 },
    { -4, 26, 55 },
    { 0, 33, 75 },
    { 2, 40, 95 },
    { 5, 50, 116 },
    { 5, 60, 138 },
    { 3, 70, 160 },
  },
  -- Out from under the skybridge the camera swings onto the spire
  aim = function(t)
    return 25, 55, 125, 0.6 * smooth((t - 4.6) / 1.2)
  end,
  level = 0.4,
  wobble = 2,
  duration = 7.4,
})

-- CITY SLOT: on from the skybridge, left into the slot between the towers
shot({
  name = "cityslot",
  mode = "freestyle",
  map = "city",
  voltage = 3.85,
  speed = 24,
  keys = {
    { 0, 34, 70 },
    { 0, 33, 80 },
    { -8, 30, 92 },
    { -20, 25, 104 },
    { -25, 22, 113 },
    { -25, 20, 125 },
    { -25, 17, 138 },
    { -25, 14, 151 },
    { -25, 11.5, 164 },
  },
})

-- OLD MILL: down past the mill's east side, low through the hay barrack, then a flaring turn round to face the
-- mill from the front
shot({
  name = "oldmill",
  mode = "freestyle",
  map = "oldmill",
  voltage = 3.8,
  speed = 14,
  keys = {
    { 16, 19, 70 },
    { 22, 15, 58 },
    { 22, 10, 46 },
    { 17, 6, 36 },
    { 16, 3.5, 26 },
    { 16, 3.5, 15 },
    { 16, 3.5, 2 },
    { 16, 4.5, -8, 12 },
    { 12, 8, -15, 9 },
    { 6, 10, -14, 6 },
    { 3, 11, -10, 3 },
  },
  -- On the mill coming down, on the barrack through it, back on the mill in the turn
  aim = function(t)
    return 0, 15, 45, math.max(0.6 * (1 - smooth((t - 1.4) / 1.0)), smooth((t - 5.0) / 1.4))
  end,
  aimPitch = true,
  level = 0.8,
  wobble = 2,
  duration = 8.5,
})

-- WIND FARM: an orbit of the high turbine, 22 m out and a little over its hub, from the south-west round the face of
-- its turning rotor to the south-east, the camera looking slightly down on the hub
local function turbineOrbit()
  local keys = {}
  for i = 0, 9 do
    local b = (225 - 10 * i) * RAD
    keys[#keys + 1] = { i * 0.6, -30 + 22 * sin(b), 27, 55 + 22 * cos(b) }
  end
  return keys
end
shot({
  name = "windfarm",
  mode = "freestyle",
  map = "windfarm",
  voltage = 3.75,
  keys = turbineOrbit(),
  aim = function()
    return -30, 23, 52
  end,
  -- A lower camera tilt than the default, so looking down on the hub keeps the quad near level
  cam = 25,
  aimPitch = true,
  level = 1,
  duration = 5.4,
})

-- OLD MILL, the other take: a banked orbit dive, high in from the south-west, down across the front of the turning
-- sails and out low past the mill's east side
shot({
  name = "oldmilldive",
  mode = "freestyle",
  map = "oldmill",
  voltage = 3.8,
  speed = 15,
  keys = {
    { -32, 30, 16 },
    { -18, 25, 22 },
    { -3, 18, 25 },
    { 11, 12, 29 },
    { 20, 8, 40 },
    { 19, 5, 53 },
    { 12, 3.5, 64 },
    { 0, 3, 72 },
  },
  aim = function(t)
    return 0, 15, 45, 0.85 * (1 - smooth((t - 4.4) / 1.0))
  end,
  aimPitch = true,
  level = 0.75,
  wobble = 2,
  duration = 4.4,
})

-- HARBOR: low under the pier between its piles, then up and round to the right over the ship's stern
shot({
  name = "harbor",
  mode = "freestyle",
  map = "harbor",
  voltage = 3.7,
  speed = 15,
  keys = {
    { -22, 1.2, -25 },
    { -22, 1.2, -5 },
    { -22, 1.2, 15 },
    { -22, 1.2, 35 },
    { -22, 1.4, 50 },
    { -19, 5, 63 },
    { -10, 11, 75 },
    { 3, 17, 79 },
    { 14, 20, 70 },
  },
  level = 0.5,
  wobble = 2,
})

-- CRASH: TECH, through the start gate and on at the ladder, a touch high for its first rung: the bar between it and
-- the second one is hit; the shot crashes where the path first hits
shot({
  name = "crash",
  mode = "racing",
  map = "tech",
  voltage = 3.6,
  speed = 16,
  keys = {
    { 0, 1.6, 4 },
    { 0, 1.7, 22 },
    { 0, 2.2, 34 },
    { 0, 2.75, 45 },
    { 0, 3, 52 },
  },
  crashOnHit = true,
  duration = 5,
})

-- Keys {x, y, z[, m/s into it]} flown at speed m/s into keys {t, x, y, z}; the shot lasts until the last key
local function timed(s)
  local out, t = {}, 0
  for i, k in ipairs(s.keys) do
    if i > 1 then
      local p = s.keys[i - 1]
      t = t + sqrt((k[1] - p[1]) ^ 2 + (k[2] - p[2]) ^ 2 + (k[3] - p[3]) ^ 2) / (k[4] or s.speed)
    end
    out[i] = { t, k[1], k[2], k[3] }
  end
  s.keys, s.duration = out, s.duration or t - 0.1
  -- A barrel roll centred on reaching that key
  if s.rollAtKey then
    local tk = out[s.rollAtKey][1]
    s.spins = { { tk - 0.45, tk + 0.45, "roll", 1 } }
  end
end
for _, s in ipairs(SHOTS) do
  if s.speed then
    timed(s)
  end
end

-- Analog video static as the link comes in, over a shot's first frames
local CUT_IN = 5
local function cutIn(f)
  if f < CUT_IN then
    gfx.static(1 - f / CUT_IN)
  end
end

-- Ink pixels of text in the big font drawn alone, as a list of x, y, and its width and height
local function bigText(text)
  gfx.clear()
  gfx.text(0, 0, text, nil, true)
  local px, w, h = {}, 0, 0
  for y = 0, 2 * gfx.FH do
    for x = 0, LCD_W - 1 do
      if H.fb[y * LCD_W + x] == 1 then
        px[#px + 1], px[#px + 2] = x, y
        w, h = math.max(w, x + 1), math.max(h, y + 1)
      end
    end
  end
  return px, w, h
end

-- Big lines drawn twice their size, a pixel block each
local function renderCard(s, frame)
  local lines = {}
  local total = 0
  for _, l in ipairs(s.card) do
    local line = { text = l[1] }
    if l[2] then
      line.px, line.w, line.h = bigText(l[1])
      line.w, line.h = 2 * line.w, 2 * line.h + 3
    else
      line.h = gfx.FH + 1
    end
    lines[#lines + 1] = line
    total = total + line.h
  end
  for f = 0, s.duration * FPS - 1 do
    H.time = math.floor(f * 100 / FPS)
    gfx.clear()
    local y = (LCD_H - total) // 2
    for _, l in ipairs(lines) do
      if l.px then
        local x0 = (LCD_W - l.w) // 2
        for i = 1, #l.px, 2 do
          gfx.rect(x0 + 2 * l.px[i], y + 2 * l.px[i + 1], 2, 2, 1)
        end
      else
        gfx.text(LCD_W / 2, y, l.text, "c")
      end
      y = y + l.h
    end
    cutIn(f)
    frame()
  end
end

local function renderMenu(s, frame)
  local tool = loadScript("/SCRIPTS/TOOLS/PropRush/main.lua")()
  tool.init()
  tool.run(0)
  tool.run(EVT_VIRTUAL_ENTER)
  local ev = s.menu
  local nextEv = 1
  for f = 0, s.duration * FPS - 1 do
    local t = f / FPS
    H.time = H.time + 100 // FPS
    local event = 0
    if ev[nextEv] and t >= ev[nextEv] then
      event, nextEv = ev[nextEv + 1], nextEv + 2
    end
    tool.run(event)
    cutIn(f)
    frame()
  end
end

-- Samples rec(Map) every step for the shot's length (plus a second) on its own copy of the map, as a function of t
local function recording(s)
  local Map = newMap(s.mode, s.map)
  local raw = {}
  local lead = math.floor((s.lead or 0) / DT + 0.5)
  local steps = lead + math.ceil((s.duration + 1) / DT)
  for i = 0, steps do
    raw[i] = s.record(Map, raw[i - 1])
    Map.update(DT, nil)
  end
  -- Gaussian over sigma seconds, so the follow path has no kinks for the attitude to jitter on
  local samples = raw
  if s.sigma then
    samples = {}
    local r = math.ceil(3 * s.sigma / DT)
    for i = 0, steps do
      local o, wsum = {}, 0
      for j = math.max(0, i - r), math.min(steps, i + r) do
        local w = math.exp(-0.5 * ((j - i) * DT / s.sigma) ^ 2)
        for c = 1, #raw[j] do
          o[c] = (o[c] or 0) + w * raw[j][c]
        end
        wsum = wsum + w
      end
      for c = 1, #o do
        o[c] = o[c] / wsum
      end
      samples[i] = o
    end
  end
  -- Catmull-Rom between the samples
  return function(t)
    local k = t / DT + lead
    local i = math.floor(k)
    i = i < 1 and 1 or i > steps - 2 and steps - 2 or i
    local u = k - i
    local p0, p1, p2, p3 = samples[i - 1], samples[i], samples[i + 1], samples[i + 2]
    local o = {}
    for c = 1, #p1 do
      local a, b, cc, d = p0[c], p1[c], p2[c], p3[c]
      o[c] = b + 0.5 * u * (cc - a + u * (2 * a - 5 * b + 4 * cc - d + u * (3 * (b - cc) + d - a)))
    end
    return table.unpack(o)
  end
end

local function renderFlight(s, frame)
  local Map = newMap(s.mode, s.map)
  local m = load("modes/" .. s.mode, Gap).new(Map, nil, highscore, s.map)
  m:reset()
  for _ = 1, math.floor((s.lead or 0) / DT + 0.5) do
    Map.update(DT, nil)
  end
  local pos
  local rec = s.record and recording(s)
  if s.pos then
    pos = function(t)
      return s.pos(t, rec)
    end
  elseif rec then
    pos = function(t)
      local x, y, z = spline(s.keys, t)
      local ax, ay, az = rec(t)
      return x + ax, y + ay, z + az
    end
  else
    pos = function(t)
      return spline(s.keys, t)
    end
  end
  local minUp, maxSpeed = 1, 0
  local q = Quad.new()
  local x, y, z = pos(0)
  local x1, _, z1 = pos(0.05)
  q:reset(x, y, z, math.atan(x1 - x, z1 - z) / RAD)
  q.armed = true
  q.voltage = s.voltage or 4.1
  local pf, pu = { q.fx, q.fy, q.fz }, { 0, 1, 0 }
  R.setView(0, 0, LCD_W, LCD_H, settings.fov, s.cam or settings.camAngle)
  local crashed, crashTime = false, 0
  for f = 0, s.duration * FPS - 1 do
    for k = 1, SUB do
      local t = (f * SUB + k) * DT
      Map.update(DT, q)
      if crashed or (s.crashAt and t >= s.crashAt) then
        if not crashed then
          crashed = true
          m:finish()
        end
        crashTime = crashTime + DT
      else
        local ox, oy, oz = q.px, q.py, q.pz
        local ax, ay, az, aw
        if s.aim then
          ax, ay, az, aw = s.aim(t, rec)
        end
        local px, py, pz, vx, vy, vz, rx, ry, rz, ux, uy, uz, fx, fy, fz = attitude(pos, t, pf, pu, ax, ay, az, aw)
        -- 1 while a flip or roll is under way (easing in and out over SPIN_FADE): levelling and easing stand aside
        local trick = 0
        for _, sp in ipairs(s.spins or {}) do
          local w = math.min(smooth((t - sp[1] + SPIN_FADE) / SPIN_FADE), 1 - smooth((t - sp[2]) / SPIN_FADE))
          trick = math.max(trick, w)
        end
        for _, sp in ipairs(s.spins or {}) do
          local th = 2 * pi * sp[4] * smooth((t - sp[1]) / (sp[2] - sp[1]))
          if sp[3] == "roll" then
            rx, ry, rz = about(rx, ry, rz, fx, fy, fz, -th)
            ux, uy, uz = about(ux, uy, uz, fx, fy, fz, -th)
          else
            ux, uy, uz = about(ux, uy, uz, rx, ry, rz, -th)
            fx, fy, fz = about(fx, fy, fz, rx, ry, rz, -th)
          end
        end
        pf[1], pf[2], pf[3] = fx, fy, fz
        pu[1], pu[2], pu[3] = ux, uy, uz
        if s.tilt then
          local a = tiltAt(s.tilt, t) * RAD
          local c, sn = cos(a), sin(a)
          fx, fy, fz, ux, uy, uz =
            fx * c - ux * sn, fy * c - uy * sn, fz * c - uz * sn, ux * c + fx * sn, uy * c + fy * sn, uz * c + fz * sn
        end
        -- Look-at in pitch too: the nose goes down (or up) until the camera's axis meets the aim point
        if ax and s.aimPitch then
          local c = (s.cam or settings.camAngle) * RAD
          local cy = fy * cos(c) + uy * sin(c)
          local _, ny = norm(ax - px, ay - py, az - pz)
          local a = (asin(cy < -1 and -1 or cy > 1 and 1 or cy) - asin(ny)) * (aw or 1)
          local co, sn = cos(a), sin(a)
          fx, fy, fz, ux, uy, uz =
            fx * co - ux * sn,
            fy * co - uy * sn,
            fz * co - uz * sn,
            ux * co + fx * sn,
            uy * co + fy * sn,
            uz * co + fz * sn
        end
        -- Horizon levelled as a gimbal would, level of the way (1: the right axis held horizontal)
        if s.level and trick < 1 then
          local lv = s.level * (1 - trick)
          local lx, _, lz = norm(fz, 0, -fx)
          rx, ry, rz = norm(rx + (lx - rx) * lv, ry * (1 - lv), rz + (lz - rz) * lv)
          ux, uy, uz = norm(fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx)
        end
        -- A pilot's thumbs: the horizon never quite still, a slow drift of up to wobble degrees in roll (half that in
        -- pitch) from out-of-step sines
        if s.wobble then
          local w = s.wobble * RAD
          local roll = w * (0.6 * sin(2 * pi * 0.31 * t) + 0.4 * sin(2 * pi * 0.77 * t + 1.3))
          local pitch = 0.5 * w * (0.6 * sin(2 * pi * 0.43 * t + 0.7) + 0.4 * sin(2 * pi * 0.91 * t + 2.1))
          rx, ry, rz = about(rx, ry, rz, fx, fy, fz, roll)
          ux, uy, uz = about(ux, uy, uz, fx, fy, fz, roll)
          ux, uy, uz = about(ux, uy, uz, rx, ry, rz, pitch)
          fx, fy, fz = about(fx, fy, fz, rx, ry, rz, pitch)
        end
        -- Steady hands: the camera eases after the attitude the path asks for rather than snapping to it
        if f > 0 or k > 1 then
          local e = 1 - math.exp(-DT / (s.ease or EASE))
          e = e + (1 - e) * trick
          fx, fy, fz = norm(q.fx + (fx - q.fx) * e, q.fy + (fy - q.fy) * e, q.fz + (fz - q.fz) * e)
          ux, uy, uz = norm(q.ux + (ux - q.ux) * e, q.uy + (uy - q.uy) * e, q.uz + (uz - q.uz) * e)
        end
        rx, ry, rz = norm(uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx)
        ux, uy, uz = fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx
        q.px, q.py, q.pz, q.vx, q.vy, q.vz = px, py, pz, vx, vy, vz
        turnTo(q, rx, ry, rz, ux, uy, uz, fx, fy, fz)
        q.throttle = 0.5
        minUp, maxSpeed = math.min(minUp, uy), math.max(maxSpeed, q:speed())
        local hit = Map.collides(px, py, pz)
        if hit and s.crashOnHit then
          crashed = true
          m:finish()
        elseif hit and not s.crashAt then
          print(string.format("%s: hits something at %.2f s (%.1f, %.1f, %.1f)", s.name, t, px, py, pz))
        end
        m:update(DT, q, ox, oy, oz)
      end
    end
    H.time = math.floor((f + 1) * 100 / FPS)
    if DEBUG then
      print(
        string.format(
          "%s %4d %.2f pos %.4f %.4f %.4f f %.6f %.6f %.6f u %.6f %.6f %.6f",
          s.name,
          f + 1,
          (f + 1) / FPS,
          q.px,
          q.py,
          q.pz,
          q.fx,
          q.fy,
          q.fz,
          q.ux,
          q.uy,
          q.uz
        )
      )
    end

    local loss, message = 0, nil
    if crashed then
      message = "CRASH"
      loss = crashTime < 0.2 and 1 or math.max(0, 1 - (crashTime - 0.2) / 1.8)
    end
    R.setCamera(q)
    if loss < 1 then
      if gfx.ground then
        gfx.ground(R)
      else
        gfx.clear()
      end
      Map.draw(settings.quality)
      m:draw(R, gfx)
    else
      gfx.clear()
    end
    if loss > 0 then
      gfx.static(loss)
    end
    Hud.draw(q, settings, m.goal, message, m.note, m.clock)
    cutIn(f)
    frame()
  end
  print(string.format("%s: up axis height down to %.2f, top speed %.0f km/h", s.name, minUp, maxSpeed * 3.6))
end

for _, s in ipairs(SHOTS) do
  if not ONLY or s.name:match("^" .. ONLY .. "$") then
    local n = 0
    local function frame()
      n = n + 1
      H.savePng(string.format("%s%s_%04d.png", OUT, s.name, n), 1, 1)
    end
    if s.card then
      renderCard(s, frame)
    elseif s.menu then
      renderMenu(s, frame)
    else
      renderFlight(s, frame)
    end
    print(string.format("%s: %d frames", s.name, n))
  end
end
exit(0)
