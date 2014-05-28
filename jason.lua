local jason = {}

local sub = string.sub
local match = string.match
local find = string.find
local len = string.len
local insert = table.insert
local byte = string.byte
local concat = table.concat

jason.NONE      = -1
jason.ANY       = 0
jason.OBJECT    = 1
jason.ARRAY     = 2
jason.STRING    = 3
jason.NUMBER    = 4
jason.BOOLEAN   = 5
jason.NULL      = 6
jason.EOF       = 7

local OPEN_ARRAY   = 0x5B
local CLOSE_ARRAY  = 0x5D
local OPEN_OBJECT  = 0x7B
local CLOSE_OBJECT = 0x7D
local NAME_SEP     = 0x3A -- colon
local VALUE_SEP    = 0x2C -- comma
local ESC_CHAR     = 0x5C -- backslash
local QUOTE        = 0x22 -- "
local TRUE_FIRST   = 0x74 -- t
local FALSE_FIRST  = 0x66 -- f
local NULL_FIRST   = 0x6E -- n

local Walker = {}

local function current_char(walker)
  return byte(walker.data, walker.position)
end

local function advance(walker, num)
  walker.position = walker.position + (num or 1)
end

-- Walk beyond all space
local function eat_space(walker)
  local pos = walker.position
  while true do
    local char = byte(walker.data, pos)
    if char == 0x20 or char == 0x0A or char == 0x0D or char == 0x09 then
      pos = pos + 1
    else
      walker.position = pos
      return
    end
  end
end

local function advance_space(walker, num)
  advance(walker, num)
  eat_space(walker)
end

function jason.walk(data)
  local walker = { position = 1, data = data }
  setmetatable(walker, { __index = Walker })
  eat_space(walker)
  return walker
end

function Walker:fork()
  local walker = { position = self.position, data = self.data }
  setmetatable(walker, { __index = Walker })
  return walker
end

function Walker:type()
  local char = current_char(self)
  if char == OPEN_OBJECT then -- {
    return jason.OBJECT
  elseif char == OPEN_ARRAY then
    return jason.ARRAY
  elseif char == QUOTE then
    return jason.STRING
  elseif char == TRUE_FIRST or char == FALSE_FIRST then
    return jason.BOOLEAN
  elseif char == NULL_FIRST then
    return jason.NULL
  elseif char == nil then
    return jason.EOF
  else
    -- Don't bother checking if it's really a number. handle_number()
    -- will throw an exception when it fails to parse it.
    return jason.NUMBER
  end
end

---- Handlers
-- All of these handlers are optimistic: They assume that you are
-- indeeed positioned at the current place.

local function handle_boolean(self, skip)
  local char = current_char(self)
  local is_true = (char == TRUE_FIRST)

  -- Assume valid JSON
  local length = (is_true and 4 or 5)
  advance_space(self, length)

  if not skip then
    return is_true
  end
end

local function handle_null(self)
  advance_space(self, 4)
end

local function handle_number(self, skip)
  local start = self.position
  local _, stop = find(self.data, '^-?%d+', start)
  assert(stop, 'expected number')

  -- Look for fractions
  local _, frac_stop = find(self.data, '^%.%d+', stop+1)
  stop = frac_stop or stop

  -- Look for exponents
  local _, exp_stop = find(self.data, '^[eE][+-]?%d+', stop+1)
  stop = exp_stop or stop

  self.position = stop + 1
  eat_space(self)

  if not skip then
    return tonumber(sub(self.data, start, stop))
  end
end

local function handle_string(self, skip)
  local start = self.position+1
  local pos = start
  local parts

  if not skip then
    -- TODO: Optimize string buffer for LuaJIT
    parts = {}
  end

  while true do
    local char = byte(self.data, pos)
    assert(char, "unclosed string")

    if char == QUOTE or char == ESC_CHAR then
      if not skip then
        insert(parts, sub(self.data, start, pos-1))
      end

      if char == QUOTE then break end

      -- Handle escape sequence
      local esc_char = byte(self.data, pos+1)
      local extra_char

      -- Advance two steps: once for the \ and once for the next char.
      pos = pos + 2

      if esc_char == 0x62 then
        extra_char = '\b'
      elseif esc_char == 0x66 then
        extra_char = '\f'
      elseif esc_char == 0x6E then
        extra_char = '\n'
      elseif esc_char == 0x72 then
        extra_char = '\r'
      elseif esc_char == 0x74 then
        extra_char = '\t'
      elseif esc_char == 0x75 then
        local hex_string = sub(self.data, pos, pos+3)
        local char_code = tonumber(hex_string, 16)
        -- TODO: Convert to proper UTF-8
        extra_char = string.char(char_code)
        pos = pos + 4
      else
        -- Don't ignore the character
        pos = pos - 1
      end

      if not skip and extra_char then
        insert(parts, extra_char)
      end

      start = pos
    end

    pos = pos + 1
  end

  self.position = pos + 1
  eat_space(self)

  if not skip then
    return concat(parts)
  end
end

local function handle_key(self, skip)
  local key = handle_string(self, skip)
  assert(current_char(self) == NAME_SEP)
  advance_space(self)
  return key
end

local function handle_object(self, skip)
  local obj = (not skip) and {}

  while self:next_item() do
    local key = handle_key(self, skip)

    if skip then
      self:skip()
    else
      obj[key] = self:read()
    end
  end

  return obj
end

local function handle_array(self, skip)
  local arr = (not skip) and {}

  while self:next_item() do
    if skip then
      self:skip()
    else
      insert(arr, self:read())
    end
  end

  return arr
end

-- Generic handler. Checks the current type and invokes the correct
-- handler. You can pass in the expected type in +exp_t+.
local function handle(self, exp_t)
  local t = self:type()
  local skip = (exp_t ~= jason.ANY) and (t ~= exp_t)

  if t == jason.OBJECT then
    return handle_object(self, skip)
  elseif t == jason.ARRAY then
    return handle_array(self, skip)
  elseif t == jason.STRING then
    return handle_string(self, skip)
  elseif t == jason.NUMBER then
    return handle_number(self, skip)
  elseif t == jason.BOOLEAN then
    return handle_boolean(self, skip)
  elseif t == jason.NULL then
    -- Doesn't really matter what we return here
    handle_null(self)
  end
end

function Walker:read()
  return handle(self, jason.ANY)
end

function Walker:read_boolean()
  return handle(self, jason.BOOLEAN)
end

function Walker:read_null()
  local is_null = (self:type() == jason.NULL)
  handle(self, jason.NONE) -- skip the value
  return is_null
end

function Walker:read_number()
  return handle(self, jason.NUMBER)
end

function Walker:read_string()
  return handle(self, jason.STRING)
end

function Walker:read_object()
  return handle(self, jason.OBJECT)
end

function Walker:read_array()
  return handle(self, jason.ARRAY)
end

function Walker:read_key()
  return handle_key(self)
end

function Walker:skip_key()
  return handle_key(self, true)
end

function Walker:skip()
  handle(self, jason.NONE)
end

function Walker:next_item()
  local char = current_char(self)

  advance_space(self)

  if char == CLOSE_OBJECT or char == CLOSE_ARRAY then
    return false
  end

  assert(char == OPEN_OBJECT or char == OPEN_ARRAY or char == VALUE_SEP)
  return true
end

function jason.decode(data)
  return jason.walk(data):read()
end

return jason

