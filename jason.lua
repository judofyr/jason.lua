local jason = {}

local sub = string.sub
local match = string.match
local find = string.find
local len = string.len
local insert = table.insert
local byte = string.byte
local concat = table.concat

jason.OBJECT    = 1
jason.ARRAY     = 2
jason.STRING    = 3
jason.NUMBER    = 4
jason.PRIMITIVE = 5
jason.EOF       = 6

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

local function set_position(walker, num)
  walker.position = num
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
  elseif char == TRUE_FIRST or char == FALSE_FIRST or char == NULL_FIRST then
    return jason.PRIMITIVE
  elseif char == nil then
    return jason.EOF
  else
    -- Don't bother checking if it's really a number. read_number()
    -- will throw an exception when it fails to parse it.
    return jason.NUMBER
  end
end


-- Primitives: true, false, null. We only parse the first char and assume
-- that it is well-formed.
function Walker:read_primitive()
  assert(self:type() == jason.PRIMITIVE)

  local char = current_char(self)
  if char == TRUE_FIRST then
    advance_space(self, 4)
    return true
  elseif char == FALSE_FIRST then
    advance_space(self, 5)
    return false
  else
    advance_space(self, 4)
    return nil
  end
end

function Walker:skip_primitive()
  self:read_primitive()
end


-- Numbers: Use a pattern to find it, then use tonumber() to read it
function Walker:skip_number()
  local _, stop = find(self.data, '^-?%d+', self.position)
  assert(stop, 'expected number')

  -- Look for fractions
  local _, frac_stop = find(self.data, '^%.%d+', stop+1)
  stop = frac_stop or stop

  -- Look for exponents
  local _, exp_stop = find(self.data, '^[eE][+-]?%d+', stop+1)
  stop = exp_stop or stop

  set_position(self, stop+1)
  eat_space(self)
  return stop
end

function Walker:read_number()
  local start = self.position
  local stop = self:skip_number()
  return tonumber(sub(self.data, start, stop))
end


function Walker:read_string(skip)
  assert(self:type() == jason.STRING)

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

  set_position(self, pos+1)
  eat_space(self)

  if not skip then
    return concat(parts)
  end
end

function Walker:skip_string()
  self:read_string(true)
end

-- Object Keys: They're just strings followed by a colon.
function Walker:read_key(skip)
  local key = self:read_string(skip) -- pass along skip
  assert(current_char(self) == NAME_SEP)
  advance_space(self)
  return key
end

function Walker:skip_key()
  self:read_key(true)
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

function Walker:skip_object()
  while self:next_item() do
    self:skip_key()
    self:skip_any()
  end
end

function Walker:skip_array()
  while self:next_item() do
    self:skip_any()
  end
end

function Walker:skip_any()
  local t = self:type()

  if t == jason.OBJECT then
    self:skip_object()
  elseif t == jason.ARRAY then
    self:skip_array()
  elseif t == jason.STRING then
    self:skip_string()
  elseif t == jason.NUMBER then
    self:skip_number()
  elseif t == jason.PRIMITIVE then
    self:skip_primitive()
  else
    return false
  end

  return true
end

function Walker:read_value()
  local t = self:type()

  if t == jason.STRING then
    return self:read_string()
  elseif t == jason.NUMBER then
    return self:read_number()
  elseif t == jason.PRIMITIVE then
    return self:read_primitive()
  else
    error('no value type at position')
  end
end

-- Very simple decoder
local function decode(walker)
  local t = walker:type()
  if t == jason.OBJECT then
    local obj = {}
    while walker:next_item() do
      local key = walker:read_key()
      obj[key] = decode(walker)
    end
    return obj
  elseif t == jason.ARRAY then
    local arr = {}
    while walker:next_item() do
      insert(arr, decode(walker))
    end
    return arr
  else
    return walker.read_value()
  end
end

function jason.decode(data)
  return decode(jason.walk(data))
end

return jason

