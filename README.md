# Jason Walker

Jason Walker gives you a way to parse JSON in Lua on-the-go:

```lua
local jason = require 'jason'

-- Start a walk
local walker = jason.walk('[{"id":123},{"id":456}]')

-- The walker starts at the beginning.
-- We can check what type is right under the cursor now:
print(walker:type() == jason.ARRAY)

-- Because we're at an array, we can use next_item() to see
-- if there's anything in the array:
while walker:next_item() then
  -- At this point the walker looks like this:
  --    [{"id":123},{"id":456}]
  --     ^
  -- We can verify that we're actually at an object:
  print(walker:type() == jason.OBJECT)

  -- And then we can iterate over the object:
  while walker:next_item() then
    -- read_key() will read the key (or throw an exception on malformed JSON):
    local key = walker:read_key()

    if key == "id" then
      -- Notice how we get type checking as-we-parse. Parsing
      -- [{"id":"123"}] with this code would lead to a type error
      -- (exception) at this point.
      print(walker:read_number())
    else
      -- It's *very* important that you always read or skip, otherwise
      -- the walker gets very confused and is completely lost when
      -- next_item() is executed again.
      walker:skip_any()
    end
  end
end
```

## API

```lua
local jason = require 'jason'


local walker = jason.walk(string) --> Walker


walker:type()
-- Returns the type of the value at the current position in the JSON.
-- This will be one of:
--   jason.OBJECT
--   jason.ARRAY
--   jason.STRING
--   jason.PRIMITIVE
--   jason.NUMBER
--   jason.EOF
-- 
-- Note that this will not be correct if you're parsing invalid JSON.


walker:fork() --> Walker
-- Returns a new independent walker from the current position. You
-- can advance the original walker without affecting the fork, and
-- vica-versa


---- Readers
-- Note that all the following methods will error() if the value under
-- the current position in the JSON is not of the expected type.

walker:read_primitive() --> true, false, or nil
-- Parses a primitive value (true, false, null) at the current position
-- in the JSON.


walker:read_number() --> number
-- Parses a number at the current position in the JSON.


walker:read_string() --> string
-- Parses a string at the current position in the JSON.


walker:read_value() --> number, string, true, false, or nil
-- Parses either a number, string, or primitive value at the current
-- position in the JSON.


walker:read_key() --> string
-- Parses an object key at the current position in the JSON.


walker:next_item() --> bool
-- Returns true if you're inside an object/array literal and there's
-- more items to the right of the current position. 


---- Skippers
-- Use skip_* instead of read_* if you don't care about the value.

walker:skip_primitive()
walker:skip_number()
walker:skip_string()
walker:skip_key()
walker:skip_object()
walker:skip_array()
walker:skip_any() -- Skips *any* value


---- Simple decoder

jason.decode(string) -> table
-- A simple decoder built on top of the walker.
```

