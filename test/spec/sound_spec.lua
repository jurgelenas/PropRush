-- Sound cues and the motor tone: what reaches playTone/playHaptic, on which channel, and when cues are dropped.

local H = dofile("test/harness.lua")
H.install(128, 64)

local settings = { sound = 2, haptic = true }
local CUES = assert(loadfile("src/SCRIPTS/TOOLS/PropRush/platform/cues.lua"))()
local Sound = assert(loadfile("src/SCRIPTS/TOOLS/PropRush/platform/sound.lua"))(settings, CUES)
local NAMES = dofile("test/cue_names.lua")
local ID = NAMES.id

local QUEUE, NOW, MOTOR = 0, PLAY_NOW, PLAY_BACKGROUND + PLAY_NOW

local function tones()
  local list = {}
  for _, a in ipairs(H.audio) do
    if a[1] == "tone" then
      list[#list + 1] = a
    end
  end
  return list
end

local function count(kind)
  local n = 0
  for _, a in ipairs(H.audio) do
    if a[1] == kind then
      n = n + 1
    end
  end
  return n
end

-- A quad as the motor reads it
local function quad(throttle)
  return { throttle = throttle, voltage = 4.2, armed = true, dead = false, strike = 0 }
end

-- Runs the motor for s seconds in 40 ms frames; returns the last tone
local function spin(q, s)
  for _ = 1, math.floor(s / 0.04 + 0.5) do
    Sound.motor(q, 0.04)
  end
  local t = tones()
  return t[#t]
end

describe("sound", function()
  before_each(function()
    settings.sound, settings.haptic = 2, true
    H.time = H.time + 1000
    Sound.stop()
    H.audio = {}
  end)

  describe("cues", function()
    it("are all named for the specs", function()
      assert.equal(#CUES, #NAMES)
    end)
    it("pack every value as given", function()
      for id, c in ipairs(CUES) do
        H.time = H.time + 1000
        Sound.stop()
        H.audio = {}
        settings.haptic = false
        Sound.cue(id)
        settings.haptic = true
        local t = tones()
        assert.equal((#c - 5) // 5, #t, NAMES[id])
        for k, tone in ipairs(t) do
          local i = 6 + (k - 1) * 5
          -- frequency, length, pause, slide, volume
          assert.same({ c[i], c[i + 1], c[i + 2], c[i + 3], c[i + 4] }, { tone[2], tone[3], tone[4], tone[6], tone[7] }, NAMES[id])
        end
      end
    end)
    it("a melody plays in the queue", function()
      Sound.cue(ID.armed)
      local t = tones()
      assert.equal(3, #t)
      assert.same({ "tone", 880, 60, 20, QUEUE, 0, 3 }, t[1])
      assert.equal(1, count("haptic"))
    end)
    it("a single hit takes the PLAY_NOW slot", function()
      Sound.gate(2, 6)
      assert.same({ "tone", 1319, 40, 0, NOW, 0, 3 }, tones()[1])
    end)
    it("with the slot busy it goes to the queue", function()
      Sound.gate(2, 6)
      Sound.gate(3, 6)
      assert.equal(QUEUE, tones()[2][5])
    end)
    it("gate blips climb a fourth through the lap", function()
      Sound.gate(2, 6)
      H.time = H.time + 10
      Sound.gate(6, 6)
      assert.equal(1319, tones()[1][2])
      assert.equal(1760, tones()[2][2])
    end)
    it("a cue that would play late is dropped", function()
      Sound.cue(ID.best)
      Sound.cue(ID.armed)
      assert.equal(6, #tones())
    end)
    it("and plays once the queue has caught up", function()
      Sound.cue(ID.best)
      H.time = H.time + 50
      Sound.cue(ID.armed)
      assert.equal(9, #tones())
    end)
    it("turns repeat the motif's first note, then the combo chime", function()
      Sound.trick(ID.roll, 3, 2)
      local t = tones()
      assert.same({ "tone", 1109, 30, 20, 2, 0, 3 }, t[1])
      assert.same({ "tone", 1480, 90, 0, QUEUE, 0, 4 }, t[2])
    end)
    it("a held trick's ticks climb", function()
      Sound.tick(ID.hangTick, 0)
      H.time = H.time + 50
      Sound.tick(ID.hangTick, 2)
      assert.equal(988, tones()[1][2])
      assert.equal(1108, tones()[2][2])
    end)
    it("every cue sends whole numbers", function()
      for _, name in ipairs({ "deny", "rev", "throttle", "respawn", "low", "empty", "range", "link", "lost" }) do
        H.time = H.time + 1000
        Sound.cue(ID[name])
      end
      for _, name in ipairs({ "flip", "flipRoll", "yaw", "trippy", "loop", "splitS", "dive", "gap", "knife" }) do
        H.time = H.time + 1000
        Sound.trick(ID[name], 1, 5)
      end
      for _, name in ipairs({ "bank", "record", "best", "start", "lap", "bestLap" }) do
        H.time = H.time + 1000
        Sound.cue(ID[name])
      end
      Sound.contact(5.3, 2.7)
      Sound.crackle(1)
      assert.is_true(#tones() > 30)
    end)
  end)

  describe("settings", function()
    it("SOUND OFF plays nothing but keeps the haptic", function()
      settings.sound = 0
      Sound.cue(ID.armed)
      Sound.motor(quad(0.5), 0.04)
      assert.equal(0, #tones())
      assert.equal(1, count("haptic"))
    end)
    it("HAPTIC OFF keeps the sound", function()
      settings.haptic = false
      Sound.cue(ID.armed)
      assert.equal(3, #tones())
      assert.equal(0, count("haptic"))
    end)
    it("NO MOTOR plays cues without the motor", function()
      settings.sound = 1
      Sound.motor(quad(0.5), 0.04)
      Sound.cue(ID.armed)
      assert.equal(3, #tones())
    end)
  end)

  describe("contacts", function()
    it("a prop strike clacks and buzzes", function()
      Sound.contact(4, 4)
      assert.same({ "tone", 1600, 30, 0, NOW, -40, 4 }, tones()[1])
      assert.same({ "haptic", 10, 0, NOW }, H.audio[1])
    end)
    it("hits are rate limited", function()
      Sound.contact(2, 0)
      Sound.contact(2, 0)
      assert.equal(1, #tones())
    end)
    it("a soft touch is silent", function()
      Sound.contact(1, 0)
      assert.equal(0, #H.audio)
    end)
  end)

  describe("motor", function()
    -- Two frames, so the wobble's up and down halves average out
    local function pitch(q, s)
      local a = spin(q, s)[2]
      Sound.motor(q, 0.04)
      local t = tones()
      return (a + t[#t][2]) / 2
    end

    it("idles low and quiet on the background slot", function()
      local q = quad(0)
      local t = spin(q, 1)
      assert.equal(MOTOR, t[5])
      assert.equal(1, t[7])
      assert.near(420, pitch(q, 0), 2)
    end)
    it("hovers near 580 Hz", function()
      assert.near(583, pitch(quad(1 / 4.5), 1), 3)
    end)
    it("punches to 900 Hz, still quiet", function()
      local q = quad(1)
      assert.near(900, pitch(q, 1), 3)
      assert.equal(1, tones()[#tones()][7])
    end)
    it("wobbles every frame", function()
      local q = quad(1 / 4.5)
      local a = spin(q, 1)[2]
      local b = spin(q, 0.04)[2]
      assert.is_true(math.abs(a - b) > 30, a .. " " .. b)
    end)
    it("spools up over a few frames", function()
      local q = quad(0)
      spin(q, 1)
      q.throttle = 1
      local f = pitch(q, 0.04)
      assert.is_true(f > 440 and f < 750, tostring(f))
    end)
    it("pitch drops as the battery sags", function()
      local q = quad(1)
      q.voltage = 3.5
      assert.near(800, pitch(q, 1), 3)
    end)
    it("winds down and stops when the battery dies", function()
      local q = quad(1)
      spin(q, 1)
      q.dead = true
      local t = spin(q, 2)
      assert.equal(0, t[3], "the last tone stops the slot")
    end)
    it("winds down and stops when disarmed", function()
      local q = quad(1)
      spin(q, 1)
      q.armed = false
      local t = spin(q, 2)
      assert.equal(0, t[3], "the last tone stops the slot")
    end)
  end)

  describe("crash", function()
    it("flushes, hits and winds the motor down from its pitch", function()
      spin(quad(1), 1)
      H.audio = {}
      Sound.crash(false)
      assert.equal("flush", H.audio[1][1])
      local t = tones()
      assert.same({ "tone", 2000, 30, 0, NOW, -60, 5 }, t[1])
      assert.near(900, t[2][2], 50)
      assert.equal(QUEUE, t[2][5])
      assert.equal(-2, t[2][6])
    end)
    it("with the battery dead only the impact", function()
      spin(quad(1), 1)
      H.audio = {}
      Sound.crash(true)
      assert.equal(1, #tones())
    end)
  end)
end)
