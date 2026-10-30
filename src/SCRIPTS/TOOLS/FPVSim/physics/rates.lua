-- Betaflight rates (applyBetaflightRates in rc.c): deg/s for stick x in -1..1.
-- rcRate, rate (super rate) and expo in hundredths, as Betaflight stores them. RC Rate stops at 2.00, below
-- Betaflight's extra boost for higher values.

local abs = math.abs

-- Betaflight's default rate_limit
local RATE_LIMIT = 1998

return function(x, rcRate, rate, expo)
  local a = abs(x)
  if expo > 0 then
    local e = expo / 100
    x = x * a * a * a * e + x * (1 - e)
  end
  local deg = 2 * rcRate * x
  if rate > 0 then
    local d = 1 - a * rate / 100
    if d < 0.01 then
      d = 0.01
    elseif d > 1 then
      d = 1
    end
    deg = deg / d
  end
  if deg > RATE_LIMIT then
    return RATE_LIMIT
  elseif deg < -RATE_LIMIT then
    return -RATE_LIMIT
  end
  return deg
end
