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

-- Writes the pairs each(put) gives, a line per put(key, value), straight to the file; nil when it cannot be opened
function Storage.write(path, each)
  local f = io.open(path, "w")
  if not f then
    return nil
  end
  each(function(key, val)
    io.write(f, key, "=", tostring(val), "\n")
  end)
  io.close(f)
  return true
end

return Storage
