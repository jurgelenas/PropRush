-- Key=value text files on the SD card, one pair per line

local Storage = {}

-- Caps a corrupt file
local READ_MAX = 1024

-- nil when the file cannot be opened
function Storage.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = io.read(f, READ_MAX)
  io.close(f)
  local kv = {}
  if not data then
    return kv
  end
  for line in string.gmatch(data, "[^\n]+") do
    local key, val = string.match(line, "^([^=]+)=(.*)$")
    if key then
      kv[key] = val
    end
  end
  return kv
end

-- Writes keys in order, skipping absent values; nil when the file cannot be opened
function Storage.write(path, keys, values)
  local f = io.open(path, "w")
  if not f then
    return nil
  end
  for i = 1, #keys do
    local val = values[keys[i]]
    if val ~= nil then
      io.write(f, keys[i], "=", tostring(val), "\n")
    end
  end
  io.close(f)
  return true
end

return Storage
