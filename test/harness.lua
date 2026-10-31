-- Runs the tool's modules on the host Lua (edgetx-cli --script) with a mocked B&W lcd.
-- Usage: edgetx-cli dev simulator ... --script test/bench.lua  (CWD = repo root)

local H = {}

-- The tool's io calls go to H.files; the harness itself writes real files
local hostIo = io

local SRC = "src"

H.stats = { lines = 0, linePixels = 0, texts = 0, rects = 0 }
H.sticks = { ail = 0, ele = 0, thr = -1024, rud = 0 }
H.time = 0
H.SOURCES = {
  { 75, "rud", "Rud" },
  { 76, "ele", "Ele" },
  { 77, "thr", "Thr" },
  { 78, "ail", "\200Ail" },
  { 79, "s1", "S1" },
  { 80, "s2", "S2" },
  { 87, "min", "MIN" },
  { 98, "sa", "SA", switch = true },
  { 99, "sb", "SB", switch = true },
  { 198, "ch1", "CH1" },
  { 199, "ch2", "CH2" },
  { 200, "ch3", "CH3" },
}
H.text = {}
H.fb = {}

local function checkCoord(v, max, what)
  -- luaL_checkunsigned accepts floats with an exact integer value
  if v ~= math.floor(v) then
    error(string.format("%s not an integer: %s", what, tostring(v)), 3)
  end
  if v < 0 or v > max then
    error(string.format("%s out of range: %d", what, v), 3)
  end
end

local function plot(x, y, flags)
  local i = math.floor(y * LCD_W + x)
  if flags & ERASE ~= 0 then
    H.fb[i] = 0
  elseif flags & FORCE ~= 0 then
    H.fb[i] = 1
  else
    H.fb[i] = 1 - (H.fb[i] or 0)
  end
end

function H.install(w, h)
  LCD_W, LCD_H = w, h
  SOLID, DOTTED, FORCE, ERASE = 0xff, 0x55, 0x02, 0x04
  SMLSIZE, RIGHT, CENTER, INVERS = 0x0200, 0x0400, 0x0800, 0x0010
  EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1001, 1002, 1003, 1004
  GREY = nil
  local s = H.stats
  lcd = {
    clear = function()
      for i = 0, w * h - 1 do
        H.fb[i] = 0
      end
    end,
    drawLine = FAST_MOCK and function() end or function(x1, y1, x2, y2, pat, flags)
      checkCoord(x1, w - 1, "x1")
      checkCoord(x2, w - 1, "x2")
      checkCoord(y1, h - 1, "y1")
      checkCoord(y2, h - 1, "y2")
      if pat ~= math.floor(pat) or flags ~= math.floor(flags) then
        error("pattern/flags not integer", 2)
      end
      H.plotLine(x1, y1, x2, y2, pat, flags)
      s.lines = s.lines + 1
      s.linePixels = s.linePixels + math.max(math.abs(x2 - x1), math.abs(y2 - y1)) + 1
    end,
    drawFilledRectangle = FAST_MOCK and function() end or function(x, y, rw, rh, flags)
      s.rects = s.rects + 1
      for yy = y, y + rh - 1 do
        for xx = x, x + rw - 1 do
          if xx >= 0 and xx < w and yy >= 0 and yy < h then
            plot(xx, yy, flags or 0)
          end
        end
      end
    end,
    drawText = function(x, y, text, flags)
      s.texts = s.texts + 1
      H.text[s.texts] = text
      if H.fonts and not FAST_MOCK then
        H.plotText(x, y, text, flags or 0)
      end
    end,
  }
  -- Sources as a Boxer lists them: id, getValue name, label; getFieldInfo finds a switch by name only
  local byId, byName = {}, {}
  for _, src in ipairs(H.SOURCES) do
    local f = { id = src[1], name = src[2], label = src[3], switch = src.switch }
    byId[f.id], byName[f.name] = f, f
  end
  -- As the firmware, switches are found by name only
  getFieldInfo = function(source)
    local f = byName[source] or byId[source] and not byId[source].switch and byId[source]
    return f and { id = f.id, name = f.name, desc = f.label }
  end
  getSourceName = function(id)
    return byId[id] and byId[id].label
  end
  sources = function()
    local i = 0
    return function()
      i = i + 1
      local src = H.SOURCES[i]
      if src then
        return src[1], src[3]
      end
    end
  end
  getValue = function(source)
    local f = byId[source]
    return H.sticks[f and f.name or source] or 0
  end
  getTime = function()
    return H.time
  end
  -- As a radio's: version, radio, major, minor, revision, osname
  H.version = { 2, 12, 5 }
  getVersion = function()
    local v = H.version
    local s = string.format("%d.%d.%d", v[1], v[2], v[3])
    return s, "boxer-" .. s, v[1], v[2], v[3], "EdgeTX"
  end
  -- Audio calls in order: { "tone", f, d, p, flags, slide, volume }, { "haptic", d, p, flags }, { "flush" }. As on
  -- the radio, a fraction in any argument is an error.
  PLAY_NOW, PLAY_BACKGROUND = 16, 32
  H.audio = {}
  local function record(kind, ...)
    for i, v in ipairs({ ... }) do
      if math.type(v) ~= "integer" and not (math.type(v) == "float" and v == math.floor(v)) then
        error(string.format("%s argument %d has no integer representation: %s", kind, i, tostring(v)), 3)
      end
    end
    H.audio[#H.audio + 1] = { kind, ... }
  end
  playTone = function(...)
    record("tone", ...)
  end
  playHaptic = function(...)
    record("haptic", ...)
  end
  flushAudio = function()
    H.audio[#H.audio + 1] = { "flush" }
  end
  H.files = {}
  -- EdgeTX io: io.read(f, n), io.write(f, ...), io.close(f)
  io = {
    open = function(path, mode)
      if mode == "r" and not H.files[path] then
        return nil
      end
      return { path = path, mode = mode, pos = 1, buf = "" }
    end,
    read = function(f, n)
      local s = string.sub(H.files[f.path], f.pos, f.pos + n - 1)
      f.pos = f.pos + #s
      return s
    end,
    write = function(f, ...)
      for _, v in ipairs({ ... }) do
        f.buf = f.buf .. tostring(v)
      end
      return f
    end,
    close = function(f)
      if f.mode == "w" then
        H.files[f.path] = f.buf
      end
    end,
  }
  loadScript = function(path)
    return assert(loadfile(SRC .. path))
  end
end

-- Mirrors lcdDrawLine: Bresenham, pattern bit chosen by the major axis coordinate % 8
function H.plotLine(x1, y1, x2, y2, pat, flags)
  local dx, dy = x2 - x1, y2 - y1
  local sx, sy = dx < 0 and -1 or 1, dy < 0 and -1 or 1
  dx, dy = math.abs(dx), math.abs(dy)
  local x, y = math.floor(x1), math.floor(y1)
  dx, dy = math.floor(dx), math.floor(dy)
  if dx >= dy then
    local e = dx // 2
    for _ = 0, dx do
      if pat == SOLID or ((1 << (x % 8)) & pat) ~= 0 then
        plot(x, y, flags)
      end
      e = e + dy
      if e >= dx and dx > 0 then
        e = e - dx
        y = y + sy
      end
      x = x + sx
    end
  else
    local e = dy // 2
    for _ = 0, dy do
      if pat == SOLID or ((1 << (y % 8)) & pat) ~= 0 then
        plot(x, y, flags)
      end
      e = e + dx
      if e >= dy then
        e = e - dy
        x = x + sx
      end
      y = y + sy
    end
  end
end

-- The firmware's B&W fonts, read from a local EdgeTX build (GPL-2.0, so not copied here): 5 column bytes a
-- character from 0x20, bit 0 the top row; an 0xff column is not part of the glyph. Index: FONTSIZE(flags) >> 8.
local FONT_DIR = "../edgetx-firmware/build/build/wasm/radio/src/bitmaps/"

function H.loadFonts(dir)
  local function read(name)
    local f = hostIo.open((dir or FONT_DIR .. (LCD_W > 128 and "212x64" or "128x64")) .. "/" .. name .. ".lbm")
    if not f then
      return nil
    end
    local t = {}
    for v in f:read("a"):gmatch("0x(%x%x)") do
      t[#t + 1] = tonumber(v, 16)
    end
    f:close()
    return t
  end
  local std, sml = read("font_05x07"), read("font_04x06")
  if std and sml then
    H.fonts = { [0] = { data = std, h = 7 }, [2] = { data = sml, h = 6, sml = true } }
  end
  return H.fonts ~= nil
end

local function plotPixel(x, y, on)
  if y >= 0 and y < LCD_H then
    H.fb[y * LCD_W + x] = on and 1 or 0
  end
end

-- Mirrors lcdPutPattern: a column before the glyph (INVERS only), the glyph's columns, a blank one after; rows from
-- one above (INVERS only) to one below, so the text's box is set or erased. Returns lcdNextPos.
local function putPattern(x, y, o, font, inv)
  local data, h = font.data, font.h
  local nextPos = x - 1
  for i = 0, 6 do
    if x < 0 or x >= LCD_W then
      x, nextPos = x + 1, nextPos + 1
      goto nextColumn
    end
    do
      local b = 0
      if i == 0 then
        if x == 0 or not inv then
          nextPos = nextPos + 1
          goto nextColumn
        end
        x = x - 1
      elseif i <= 5 then
        o = o + 1
        b = data[o]
        if b == 0xff then
          goto nextColumn
        end
      end
      for j = -1, h do
        if j < 0 or (j == h and not font.sml) then
          if not ((j < 0 and not inv) or y + j < 0) then
            plotPixel(x, y + j, inv)
          end
        else
          plotPixel(x, y + j, (b & (1 << j) ~= 0) ~= inv)
        end
      end
      x, nextPos = x + 1, nextPos + 1
    end
    ::nextColumn::
  end
  return nextPos
end

-- Mirrors lcdDrawSizedText for printable ASCII: RIGHT and CENTER from getTextWidth (glyph columns + 1 a character)
function H.plotText(x, y, text, flags)
  if x ~= math.floor(x) or y ~= math.floor(y) then
    error(string.format("text position not an integer: %s, %s", tostring(x), tostring(y)), 3)
  end
  local font = H.fonts[flags & SMLSIZE ~= 0 and 2 or 0]
  local inv = flags & INVERS ~= 0
  if flags & (RIGHT | CENTER) ~= 0 then
    local width = 0
    for i = 1, #text do
      local o = (text:byte(i) - 0x20) * 5
      for col = 1, 5 do
        if font.data[o + col] ~= 0xff then
          width = width + 1
        end
      end
      width = width + 1
    end
    x = flags & RIGHT ~= 0 and x - width or x - width // 2
  end
  for i = 1, #text do
    local c = text:byte(i)
    if c < 0x20 or c > 0x7e then
      error(string.format("character %d not drawn by the mock: %q", c, text), 3)
    end
    x = putPattern(x, y, (c - 0x20) * 5, font, inv)
  end
end

-- edgetx-cli's LCD look (src/simulator/framebuffer.rs, decode_lcd): ink on the backlight, and above 2x a
-- dot-matrix grid between pixels, stronger over dark ones
local BACKLIGHT, INK, GRID = { 0xC9, 0xCB, 0xBA }, { 0x1A, 0x1E, 0x16 }, { 0x90, 0x92, 0x88 }
local GRID_ALPHA = 0.35

local function gridLut(scale)
  local lut = {}
  local function smoothstep(e0, e1, v)
    local t = math.min(math.max((v - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
  end
  for sy = 0, scale - 1 do
    for sx = 0, scale - 1 do
      local a = 0
      if scale <= 2 then
        if sx == scale - 1 or sy == scale - 1 then
          a = GRID_ALPHA
        end
      else
        local dx = 0.5 - math.abs((sx + 0.5) / scale - 0.5)
        local dy = 0.5 - math.abs((sy + 0.5) / scale - 0.5)
        a = math.max(1 - smoothstep(0, 0.3, dx), 1 - smoothstep(0, 0.3, dy)) * GRID_ALPHA
      end
      lut[sy * scale + sx] = a
    end
  end
  return lut
end

local CRC = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    c = c & 1 ~= 0 and 0xEDB88320 ~ (c >> 1) or c >> 1
  end
  CRC[n] = c
end

local function chunk(kind, data)
  local c = 0xFFFFFFFF
  local s = kind .. data
  for i = 1, #s do
    c = CRC[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8)
  end
  return string.pack(">I4", #data) .. s .. string.pack(">I4", c ~ 0xFFFFFFFF)
end

local LEN_BASE =
  { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
-- stylua: ignore
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
  4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }

-- zlib stream of one fixed-Huffman deflate block whose matches only repeat the byte before or the row above: all a
-- frame buffer needs
local function deflate(raw, stride)
  local out, acc, nbits = {}, 0, 0
  -- Values go in least significant bit first, Huffman codes most significant first
  local function bits(v, n)
    acc, nbits = acc | (v << nbits), nbits + n
    while nbits >= 8 do
      out[#out + 1] = string.char(acc & 0xFF)
      acc, nbits = acc >> 8, nbits - 8
    end
  end
  local function code(c, n)
    local r = 0
    for _ = 1, n do
      r, c = (r << 1) | (c & 1), c >> 1
    end
    bits(r, n)
  end
  local function symbol(v)
    if v < 144 then
      code(0x30 + v, 8)
    elseif v < 256 then
      code(0x190 + v - 144, 9)
    elseif v < 280 then
      code(v - 256, 7)
    else
      code(0xC0 + v - 280, 8)
    end
  end
  local function index(base, v)
    local k = #base
    while base[k] > v do
      k = k - 1
    end
    return k
  end
  -- Final block, fixed Huffman codes
  bits(3, 3)
  local n, i = #raw, 1
  while i <= n do
    local best, dist = 0, 0
    for _, d in ipairs({ 1, stride }) do
      if i > d then
        local l = 0
        while l < 258 and i + l <= n and raw[i + l] == raw[i + l - d] do
          l = l + 1
        end
        if l > best then
          best, dist = l, d
        end
      end
    end
    if best >= 3 then
      local li, di = index(LEN_BASE, best), index(DIST_BASE, dist)
      symbol(256 + li)
      bits(best - LEN_BASE[li], LEN_EXTRA[li])
      code(di - 1, 5)
      bits(dist - DIST_BASE[di], DIST_EXTRA[di])
      i = i + best
    else
      symbol(raw[i])
      i = i + 1
    end
  end
  symbol(256)
  bits(0, (8 - nbits) % 8)
  local a, b = 1, 0
  for k = 1, n do
    a = (a + raw[k]) % 65521
    b = (b + a) % 65521
  end
  return "\120\1" .. table.concat(out) .. string.pack(">I4", (b << 16) | a)
end

-- PNG of the frame buffer as the simulator window shows it: the grid at scale (the window's floor(480 / LCD_W)),
-- then each pixel zoom times (default 2, a HiDPI screen); savePng(path, 1, 1) is the plain LCD. Indexed colour.
function H.savePng(path, scale, zoom)
  scale = scale or math.max(1, 480 // LCD_W)
  zoom = zoom or 2
  local lut = scale > 1 and gridLut(scale)
  -- Palette index of each dot pixel, ink or not
  local palette, byColour, dots = {}, {}, {}
  for _, on in ipairs({ 0, 1 }) do
    local base = on == 1 and INK or BACKLIGHT
    local lum = (0.299 * base[1] + 0.587 * base[2] + 0.114 * base[3]) / 255
    dots[on] = {}
    for k = 0, (lut and scale * scale or 1) - 1 do
      local blend = lut and lut[k] * (0.25 + 0.75 * (1 - lum)) or 0
      local px = {}
      for ch = 1, 3 do
        px[ch] = math.floor(base[ch] * (1 - blend) + GRID[ch] * blend)
      end
      local rgb = string.char(px[1], px[2], px[3])
      if not byColour[rgb] then
        palette[#palette + 1] = rgb
        byColour[rgb] = #palette - 1
      end
      dots[on][k] = byColour[rgb]
    end
  end
  local depth = #palette <= 2 and 1 or #palette <= 4 and 2 or #palette <= 16 and 4 or 8
  local w, h = LCD_W * scale * zoom, LCD_H * scale * zoom
  local stride = (w * depth + 7) // 8 + 1
  local raw = {}
  for oy = 0, h - 1 do
    local ty = oy // zoom
    local y, sy = ty // scale, ty % scale
    raw[#raw + 1] = 0
    local byte, used = 0, 0
    for ox = 0, w - 1 do
      local tx = ox // zoom
      byte, used =
        (byte << depth) | dots[H.fb[y * LCD_W + tx // scale] == 1 and 1 or 0][sy * scale + tx % scale], used + depth
      if used == 8 then
        raw[#raw + 1], byte, used = byte, 0, 0
      end
    end
    if used > 0 then
      raw[#raw + 1] = byte << (8 - used)
    end
  end
  local f = assert(hostIo.open(path, "wb"))
  f:write("\137PNG\r\n\26\n", chunk("IHDR", string.pack(">I4I4BBBBB", w, h, depth, 3, 0, 0, 0)))
  f:write(chunk("PLTE", table.concat(palette)), chunk("IDAT", deflate(raw, stride)), chunk("IEND", ""))
  f:close()
end

function H.resetStats()
  for k in pairs(H.text) do
    H.text[k] = nil
  end
  for k in pairs(H.stats) do
    H.stats[k] = 0
  end
end

return H
