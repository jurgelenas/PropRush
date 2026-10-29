-- Runs the specs in test/spec on the host Lua (edgetx-cli --script, CWD = repo root). SPEC=name runs only the
-- files whose name contains it.

local Spec = dofile("test/spec.lua")

local filter = os.getenv("SPEC")
local files = {}
local ls = io.popen("ls test/spec/*_spec.lua")
for file in ls:lines() do
  if not filter or filter == "" or string.find(file, filter, 1, true) then
    files[#files + 1] = file
  end
end
ls:close()

exit(Spec.run(files) and 0 or 1)
