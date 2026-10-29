-- Renderer backend for monochrome and 4-bit greyscale LCDs (128x64, 212x64).

local floor = math.floor
local drawLine, drawText, drawFilledRectangle = lcd.drawLine, lcd.drawText, lcd.drawFilledRectangle

local W, H = LCD_W, LCD_H
local XMAX, YMAX = W - 1, H - 1

local Gfx = { W = W, H = H, FH = 6 }

-- drawLine patterns are matched against absolute x % 8, so per-row patterns tile into a dither.
local DITHER = {
  { 0x11, 0x00, 0x44, 0x00 },
  { 0x55, 0xAA, 0x55, 0xAA },
  { 0x77, 0xDD, 0x77, 0xDD },
}
local LINE_PATTERN = { [0] = SOLID, 0x11, DOTTED, 0x77, SOLID }

-- Greyscale LCDs: GREY(0) is black, GREY(15) white
local greyFlags
if GREY then
  greyFlags = { FORCE + GREY(12), FORCE + GREY(8), FORCE + GREY(4) }
end

local function span(xl, xr, y, shade)
  if shade >= 4 then
    drawLine(xl, y, xr, y, SOLID, FORCE)
  elseif greyFlags then
    drawLine(xl, y, xr, y, SOLID, greyFlags[shade])
  else
    local pat = DITHER[shade][y % 4 + 1]
    if pat ~= 0 then
      drawLine(xl, y, xr, y, pat, FORCE)
    end
  end
end

-- White fills are always outlined afterwards, so they are erased in blocks of rows: one rectangle per block,
-- inset to the narrowest row so nothing outside the polygon is touched. Equal consecutive blocks are merged.
local ERASE_BLOCK = 4

local function eraseFill(xs, ys, n, top, bot, r0, r1)
  local ia, ja = top, top % n + 1
  local ib, jb = top, (top - 2) % n + 1
  local runL, runR, runY, runH = 0, -1, 0, 0
  local y = r0
  while y <= r1 do
    local h = r1 - y + 1
    if h > ERASE_BLOCK then
      h = ERASE_BLOCK
    end
    local yc = y + h / 2
    while ys[ja] < yc and ja ~= bot do
      ia, ja = ja, ja % n + 1
    end
    while ys[jb] < yc and jb ~= bot do
      ib, jb = jb, (jb - 2) % n + 1
    end
    local ya, yb = ys[ia], ys[ja]
    local xa, da = xs[ia], 0
    if yb > ya then
      da = (xs[ja] - xa) / (yb - ya)
      xa = xa + (yc - ya) * da
    end
    ya, yb = ys[ib], ys[jb]
    local xb, db = xs[ib], 0
    if yb > ya then
      db = (xs[jb] - xb) / (yb - ya)
      xb = xb + (yc - ya) * db
    end
    if xa > xb then
      xa, xb, da, db = xb, xa, db, da
    end
    -- Inset by how far each edge moves between the block centre and its outermost row
    local half = (h - 1) / 2
    xa = xa + (da < 0 and -da or da) * half
    xb = xb - (db < 0 and -db or db) * half
    local xl, xr = (xa + 0.5) // 1, (xb - 0.5) // 1
    if xl < 0 then
      xl = 0
    end
    if xr > XMAX then
      xr = XMAX
    end
    if xl == runL and xr == runR and y == runY + runH then
      runH = runH + h
    else
      if runR >= runL and runH > 0 then
        drawFilledRectangle(runL, runY, runR - runL + 1, runH, ERASE)
      end
      runL, runR, runY, runH = xl, xr, y, h
    end
    y = y + h
  end
  if runR >= runL and runH > 0 then
    drawFilledRectangle(runL, runY, runR - runL + 1, runH, ERASE)
  end
end

-- Convex polygon: walk both vertex chains down from the top vertex, one span per row.
-- Rows are sampled at their centres; x is stepped incrementally along the current edge of each chain.
function Gfx.fill(xs, ys, n, shade, opaque)
  local top, bot = 1, 1
  local ytop, ybot = ys[1], ys[1]
  for i = 2, n do
    local y = ys[i]
    if y < ytop then
      top, ytop = i, y
    end
    if y > ybot then
      bot, ybot = i, y
    end
  end
  local r0 = (ytop + 0.5) // 1
  local r1 = (ybot - 0.5) // 1
  if r0 < 0 then
    r0 = 0
  end
  if r1 > YMAX then
    r1 = YMAX
  end
  if r0 > r1 then
    return
  end
  if shade == 0 and opaque == true then
    eraseFill(xs, ys, n, top, bot, r0, r1)
    return
  end

  local yc = r0 + 0.5
  local ia, ja = top, top % n + 1
  while ys[ja] < yc and ja ~= bot do
    ia, ja = ja, ja % n + 1
  end
  local ib, jb = top, (top - 2) % n + 1
  while ys[jb] < yc and jb ~= bot do
    ib, jb = jb, (jb - 2) % n + 1
  end
  local yaEnd, ybEnd = ys[ja], ys[jb]
  local da, db = 0, 0
  if yaEnd > ys[ia] then
    da = (xs[ja] - xs[ia]) / (yaEnd - ys[ia])
  end
  if ybEnd > ys[ib] then
    db = (xs[jb] - xs[ib]) / (ybEnd - ys[ib])
  end
  local xa = xs[ia] + (yc - ys[ia]) * da
  local xb = xs[ib] + (yc - ys[ib]) * db

  for y = r0, r1 do
    if yc > yaEnd and ja ~= bot then
      ia, ja = ja, ja % n + 1
      while ys[ja] < yc and ja ~= bot do
        ia, ja = ja, ja % n + 1
      end
      yaEnd = ys[ja]
      da = yaEnd > ys[ia] and (xs[ja] - xs[ia]) / (yaEnd - ys[ia]) or 0
      xa = xs[ia] + (yc - ys[ia]) * da
    end
    if yc > ybEnd and jb ~= bot then
      ib, jb = jb, (jb - 2) % n + 1
      while ys[jb] < yc and jb ~= bot do
        ib, jb = jb, (jb - 2) % n + 1
      end
      ybEnd = ys[jb]
      db = ybEnd > ys[ib] and (xs[jb] - xs[ib]) / (ybEnd - ys[ib]) or 0
      xb = xs[ib] + (yc - ys[ib]) * db
    end
    local xl, xr
    if xa < xb then
      xl, xr = (xa + 0.5) // 1, (xb - 0.5) // 1
    else
      xl, xr = (xb + 0.5) // 1, (xa - 0.5) // 1
    end
    if xl < 0 then
      xl = 0
    end
    if xr > XMAX then
      xr = XMAX
    end
    if xl <= xr then
      if opaque then
        drawLine(xl, y, xr, y, SOLID, ERASE)
      end
      if shade > 0 then
        span(xl, xr, y, shade)
      end
    end
    xa, xb, yc = xa + da, xb + db, yc + 1
  end
end

local function outcode(x, y)
  local c = 0
  if x < 0 then
    c = 1
  elseif x > XMAX then
    c = 2
  end
  if y < 0 then
    c = c + 4
  elseif y > YMAX then
    c = c + 8
  end
  return c
end

-- Cohen-Sutherland: drawLine silently drops lines with any endpoint off screen.
function Gfx.line(x1, y1, x2, y2, shade)
  if x1 >= 0 and x1 <= XMAX and x2 >= 0 and x2 <= XMAX and y1 >= 0 and y1 <= YMAX and y2 >= 0 and y2 <= YMAX then
    drawLine(
      (x1 + 0.5) // 1,
      (y1 + 0.5) // 1,
      (x2 + 0.5) // 1,
      (y2 + 0.5) // 1,
      LINE_PATTERN[shade],
      shade == 0 and ERASE or FORCE
    )
    return
  end
  local c1, c2 = outcode(x1, y1), outcode(x2, y2)
  while c1 + c2 > 0 do
    if c1 & c2 ~= 0 then
      return
    end
    local c = c1 > 0 and c1 or c2
    local x, y
    if c & 8 ~= 0 then
      x, y = x1 + (x2 - x1) * (YMAX - y1) / (y2 - y1), YMAX
    elseif c & 4 ~= 0 then
      x, y = x1 + (x2 - x1) * (0 - y1) / (y2 - y1), 0
    elseif c & 2 ~= 0 then
      x, y = XMAX, y1 + (y2 - y1) * (XMAX - x1) / (x2 - x1)
    else
      x, y = 0, y1 + (y2 - y1) * (0 - x1) / (x2 - x1)
    end
    if c == c1 then
      x1, y1 = x, y
      c1 = outcode(x1, y1)
    else
      x2, y2 = x, y
      c2 = outcode(x2, y2)
    end
  end
  drawLine(
    (x1 + 0.5) // 1,
    (y1 + 0.5) // 1,
    (x2 + 0.5) // 1,
    (y2 + 0.5) // 1,
    LINE_PATTERN[shade],
    shade == 0 and ERASE or FORCE
  )
end

function Gfx.clear()
  lcd.clear()
end

function Gfx.rect(x, y, w, h, shade)
  if shade == 0 then
    drawFilledRectangle(x, y, w, h, ERASE)
  else
    drawFilledRectangle(x, y, w, h, FORCE)
  end
end

-- align: nil left, "r" right, "c" centre; big: larger font
function Gfx.text(x, y, s, align, big, inverse)
  local flags = big and 0 or SMLSIZE
  if align == "r" then
    flags = flags + RIGHT
  elseif align == "c" then
    flags = flags + CENTER
  end
  if inverse then
    flags = flags + INVERS
  end
  drawText(x, y, s, flags)
end

return Gfx
