-- Runs the tool's modules on the host Lua (edgetx-cli --script) with a mocked B&W lcd.
-- Usage: edgetx-cli dev simulator ... --script test/bench.lua  (CWD = repo root)

local H = {}

-- The tool's io calls go to H.files; the harness itself writes real files
local hostIo = io

local SRC = "src"

H.stats = { lines = 0, linePixels = 0, texts = 0, rects = 0 }
H.sticks = { ail = 0, ele = 0, thr = -1024, rud = 0 }
H.time = 0
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
    drawText = function(_, _, text)
      s.texts = s.texts + 1
      H.text[s.texts] = text
    end,
  }
  getValue = function(name)
    return H.sticks[name]
  end
  getTime = function()
    return H.time
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

function H.savePbm(path)
  local out = { string.format("P1\n%d %d\n", LCD_W, LCD_H) }
  for y = 0, LCD_H - 1 do
    local row = {}
    for x = 0, LCD_W - 1 do
      row[#row + 1] = H.fb[y * LCD_W + x] == 1 and "1" or "0"
    end
    out[#out + 1] = table.concat(row, " ") .. "\n"
  end
  local f = assert(hostIo.open(path, "w"))
  f:write(table.concat(out))
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
