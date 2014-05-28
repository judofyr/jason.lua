# Jason Walker

Jason Walker gives you a way to parse JSON in Lua on-the-go:

```lua
local jason = require 'jason'

-- Start a walk
local walker = jason.walk('[{"id":123},{"id":456}]')

-- The walker starts at the beginning.
-- We can check what type is right under the cursor now:
assert(walker:type() == jason.ARRAY)

-- Because we're at an array, we can use next_item() to see
-- if there's anything in the array:
for idx in walker:iter_array() do
  -- At this point the walker looks like this:
  --    [{"id":123},{"id":456}]
  --     ^
  -- We can verify that we're actually at an object:
  assert(walker:type() == jason.OBJECT)

  -- And then we can iterate over the object:
  for key in walker:iter_object() do
    if key == "id" then
      -- Notice how we get type checking as-we-parse. Parsing
      -- [{"id":"123"}] with this code would lead to a type error
      -- (exception) at this point.
      print(assert(walker:read_number()))
    else
      -- It's *very* important that you always read or skip, otherwise
      -- the walker gets very confused and is completely lost when
      -- next_item() is executed again.
      walker:skip()
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
--   jason.BOOLEAN
--   jason.NULL
--   jason.NUMBER
--   jason.EOF
--
-- Note that this will not be correct if you're parsing invalid JSON.


walker:fork() --> Walker
-- Returns a new independent walker from the current position. You
-- can advance the original walker without affecting the fork, and
-- vica-versa


---- Readers
-- Note that all of the following methods will return +nil+ if the value
-- under the current position in the JSON is not of the expected type.


walker:read() --> table, number, string, true, false, nil
-- Parses either an object, array or primitive value at the current
-- position in the JSON.


walker:read_object() --> table
-- Parses an object at the current position in the JSON.


walker:read_array() --> table
-- Parses an array at the current position in the JSON.


walker:read_boolean() --> true, false
-- Parses a boolean at the current position in the JSON.


walker:read_null() --> true
-- Parses a null value and returns true.


walker:read_number() --> number
-- Parses a number at the current position in the JSON.


walker:read_string() --> string
-- Parses a string at the current position in the JSON.


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

