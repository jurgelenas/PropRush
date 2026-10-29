-- A small busted-style test framework: describe / it / pending / before_each / after_each, and assert with
-- matchers (assert.equal, assert.are.same, assert.is_not.near, ...). Specs run in the order written, so later
-- tests may build on the state earlier ones left.

local Spec = {}

-- The harness swaps io for the EdgeTX file API
local write = io.write

local function block(name, parent)
  return { name = name, parent = parent, children = {}, before = {}, after = {} }
end

local current

function describe(name, fn)
  local b = block(name, current)
  current.children[#current.children + 1] = b
  current = b
  fn()
  current = b.parent
end

function it(name, fn)
  current.children[#current.children + 1] = { name = name, fn = fn, parent = current }
end

function pending(name)
  current.children[#current.children + 1] = { name = name, parent = current }
end

function before_each(fn)
  current.before[#current.before + 1] = fn
end

function after_each(fn)
  current.after[#current.after + 1] = fn
end

-- Assertions ------------------------------------------------------------------------------------------------------

-- Set by a failed assertion, so the runner tells failures from errors
local failed

local function show(v)
  if type(v) == "string" then
    return string.format("(string) '%s'", v)
  end
  return string.format("(%s) %s", type(v), tostring(v))
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- name = { number of arguments, test, what is expected }; the argument after them is an optional message
local MATCHERS = {
  equal = {
    2,
    function(e, a)
      return e == a
    end,
    "objects to %sbe equal",
  },
  same = { 2, same, "objects to %sbe the same" },
  near = {
    3,
    function(e, a, tol)
      return type(a) == "number" and math.abs(e - a) <= tol
    end,
    "values to %sbe near",
  },
  truthy = {
    1,
    function(v)
      return v ~= nil and v ~= false
    end,
    "to %sbe truthy",
  },
  falsy = {
    1,
    function(v)
      return v == nil or v == false
    end,
    "to %sbe falsy",
  },
  ["true"] = {
    1,
    function(v)
      return v == true
    end,
    "to %sbe true",
  },
  ["false"] = {
    1,
    function(v)
      return v == false
    end,
    "to %sbe false",
  },
  ["nil"] = {
    1,
    function(v)
      return v == nil
    end,
    "to %sbe nil",
  },
  matches = {
    2,
    function(pattern, s)
      return type(s) == "string" and string.find(s, pattern) ~= nil
    end,
    "string to %smatch",
  },
  error = {
    1,
    function(fn)
      return not pcall(fn)
    end,
    "function to %sraise an error",
  },
}
MATCHERS.equals = MATCHERS.equal
MATCHERS.has_error = MATCHERS.error

local function matcher(m, negate)
  local n, test, what = m[1], m[2], m[3]
  return function(...)
    local args = { ... }
    if (not not test(...)) == negate then
      local lines = { string.format("Expected " .. what .. ".", negate and "not " or "") }
      if args[n + 1] then
        table.insert(lines, 1, tostring(args[n + 1]))
      end
      if n == 1 then
        lines[#lines + 1] = "Passed in: " .. show(args[1])
      else
        lines[#lines + 1] = "Passed in: " .. show(args[2])
        lines[#lines + 1] = "Expected: " .. show(args[1]) .. (n == 3 and " +/- " .. tostring(args[3]) or "")
      end
      failed = true
      error(table.concat(lines, "\n"), 2)
    end
  end
end

local function matchers(negate)
  local t = {}
  for name, m in pairs(MATCHERS) do
    t[name] = matcher(m, negate)
  end
  return t
end

local is, isNot = matchers(false), matchers(true)
is.are, is.is, is.is_not, is.are_not = is, is, isNot, isNot
for name in pairs(MATCHERS) do
  is["is_" .. name], is["is_not_" .. name] = is[name], isNot[name]
  is["are_" .. name], is["are_not_" .. name] = is[name], isNot[name]
end

assert = setmetatable(is, {
  __call = function(_, v, msg, ...)
    if not v then
      failed = true
      error(msg or "assertion failed!", 2)
    end
    return v, msg, ...
  end,
})

-- Running ---------------------------------------------------------------------------------------------------------

local MARK = { success = "●", failure = "◼", error = "✱", pending = "◌" }

local function fullName(t)
  local names = {}
  while t and t.name do
    table.insert(names, 1, t.name)
    t = t.parent
  end
  return table.concat(names, " ")
end

local function hooks(b, key, list)
  if b.parent then
    hooks(b.parent, key, list)
  end
  for _, fn in ipairs(b[key]) do
    list[#list + 1] = fn
  end
  return list
end

local function call(fn)
  failed = false
  local ok, err = pcall(fn)
  if ok then
    return "success"
  end
  return failed and "failure" or "error", tostring(err)
end

local function runTest(t, results)
  local status, err
  if not t.fn then
    status = "pending"
  else
    for _, fn in ipairs(hooks(t.parent, "before", {})) do
      status, err = call(fn)
      if status ~= "success" then
        break
      end
    end
    if status == nil or status == "success" then
      status, err = call(t.fn)
    end
    local after = hooks(t.parent, "after", {})
    for i = #after, 1, -1 do
      local s, e = call(after[i])
      if s ~= "success" and status == "success" then
        status, err = s, e
      end
    end
  end
  write(MARK[status])
  results[status] = results[status] + 1
  if status == "failure" or status == "error" then
    results.reports[#results.reports + 1] = { status = status, name = fullName(t), err = err }
  end
end

local function runBlock(b, results)
  for _, child in ipairs(b.children) do
    if child.children then
      runBlock(child, results)
    else
      runTest(child, results)
    end
  end
end

-- Loads and runs each spec file in turn (a file's top level sets up what its tests share); true when all passed
function Spec.run(files)
  local results = { success = 0, failure = 0, error = 0, pending = 0, reports = {} }
  local t0 = os.clock()
  for _, file in ipairs(files) do
    local root = block(nil, nil)
    current = root
    local chunk, err = loadfile(file)
    local ok = chunk ~= nil
    if ok then
      ok, err = pcall(chunk)
    end
    if ok then
      runBlock(root, results)
    else
      write(MARK.error)
      results.error = results.error + 1
      results.reports[#results.reports + 1] = { status = "error", name = file, err = tostring(err) }
    end
  end
  print("")
  for _, r in ipairs(results.reports) do
    print(string.format("\n%s → %s\n%s", r.status == "failure" and "Failure" or "Error", r.name, r.err))
  end
  local function count(n, one, many)
    return string.format("%d %s", n, n == 1 and one or many)
  end
  print(
    string.format(
      "\n%s / %s / %s / %s : %.2f seconds",
      count(results.success, "success", "successes"),
      count(results.failure, "failure", "failures"),
      count(results.error, "error", "errors"),
      count(results.pending, "pending", "pending"),
      os.clock() - t0
    )
  )
  return results.failure == 0 and results.error == 0
end

return Spec
