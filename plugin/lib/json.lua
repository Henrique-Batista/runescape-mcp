-- Minimal JSON encoder/decoder for Lua 5.4.
-- Supports objects, arrays, strings, numbers, booleans and null.
local json = {}

local function is_array(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
      return false
    end
    if k > n then n = k end
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

function json.encode(value)
  local t = type(value)
  if value == nil then
    return "null"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  elseif t == "string" then
    local s = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. s .. '"'
  elseif t == "table" then
    if is_array(value) then
      local parts = {}
      for i = 1, #value do
        parts[i] = json.encode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(value) do
        if type(k) == "string" then
          parts[#parts + 1] = json.encode(k) .. ":" .. json.encode(v)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return "null"
  end
end

-- Decoder
local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      i = i + 1
    else
      break
    end
  end
  return i
end

local parse_value

local function parse_string(s, i)
  -- assumes s:sub(i,i) == '"'
  i = i + 1
  local buf = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(buf), i + 1
    elseif c == "\\" then
      local e = s:sub(i + 1, i + 1)
      if e == "n" then buf[#buf + 1] = "\n"; i = i + 2
      elseif e == "r" then buf[#buf + 1] = "\r"; i = i + 2
      elseif e == "t" then buf[#buf + 1] = "\t"; i = i + 2
      elseif e == '"' or e == "\\" or e == "/" then buf[#buf + 1] = e; i = i + 2
      elseif e == "u" then
        -- basic unicode: just skip 4 hex, store replacement char approx
        local hex = s:sub(i + 2, i + 5)
        local code = tonumber(hex, 16)
        if code then
          if code < 128 then
            buf[#buf + 1] = string.char(code)
          else
            buf[#buf + 1] = "?"
          end
        end
        i = i + 6
      else
        buf[#buf + 1] = e
        i = i + 2
      end
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  error("unterminated string")
end

local function parse_number(s, i)
  local j = i
  while j <= #s do
    local c = s:sub(j, j)
    if c:match("[%d%.%+%-eE]") then
      j = j + 1
    else
      break
    end
  end
  local num = tonumber(s:sub(i, j - 1))
  if num == nil then error("invalid number") end
  return num, j
end

local function parse_array(s, i)
  i = skip_ws(s, i + 1) -- skip [
  local arr = {}
  if s:sub(i, i) == "]" then
    return arr, i + 1
  end
  while true do
    local v, ni = parse_value(s, i)
    arr[#arr + 1] = v
    i = skip_ws(s, ni)
    local c = s:sub(i, i)
    if c == "]" then
      return arr, i + 1
    elseif c == "," then
      i = skip_ws(s, i + 1)
    else
      error("expected , or ]")
    end
  end
end

local function parse_object(s, i)
  i = skip_ws(s, i + 1) -- skip {
  local obj = {}
  if s:sub(i, i) == "}" then
    return obj, i + 1
  end
  while true do
    i = skip_ws(s, i)
    if s:sub(i, i) ~= '"' then error("expected string key") end
    local key, ni = parse_string(s, i)
    i = skip_ws(s, ni)
    if s:sub(i, i) ~= ":" then error("expected :") end
    i = skip_ws(s, i + 1)
    local val, n2 = parse_value(s, i)
    obj[key] = val
    i = skip_ws(s, n2)
    local c = s:sub(i, i)
    if c == "}" then
      return obj, i + 1
    elseif c == "," then
      i = skip_ws(s, i + 1)
    else
      error("expected , or }")
    end
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    return parse_object(s, i)
  elseif c == "[" then
    return parse_array(s, i)
  elseif c == '"' then
    return parse_string(s, i)
  elseif c == "t" then
    if s:sub(i, i + 3) == "true" then
      return true, i + 4
    end
    error("invalid literal")
  elseif c == "f" then
    if s:sub(i, i + 4) == "false" then
      return false, i + 5
    end
    error("invalid literal")
  elseif c == "n" then
    if s:sub(i, i + 3) == "null" then
      return nil, i + 4
    end
    error("invalid literal")
  else
    return parse_number(s, i)
  end
end

function json.decode(s)
  if type(s) ~= "string" then return nil end
  local ok, v, i = pcall(parse_value, s, 1)
  if not ok then return nil, v end
  return v
end

return json