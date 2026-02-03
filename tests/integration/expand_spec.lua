local helpers = require("tests.helpers")
local kwargs = require("kwargs")

describe("expand_keywords", function()
  after_each(function()
    helpers.teardown()
  end)

  local function test_expand(description, input, expected, call_pattern)
    it(description, function()
      helpers.setup_python_file(input)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      -- Position cursor on the call
      local found = helpers.cursor_on_call(call_pattern or "result = ")
      assert.is_true(found, "Should find call pattern")

      -- Run expand
      kwargs.expand_keywords()

      -- Small wait for buffer update
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(expected, content)
    end)
  end

  -- Basic cases
  test_expand(
    "expands simple positional arguments",
    [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]]
  )

  test_expand(
    "expands with some kwargs already present",
    [[
def foo(a, b, c):
    pass

result = foo(1, b=2, c=3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]]
  )

  test_expand(
    "does not expand already-keyworded arguments",
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]]
  )

  -- Positional-only parameters (/)
  test_expand(
    "does NOT expand positional-only arguments (before /)",
    [[
def foo(a, b, /, c, d):
    pass

result = foo(1, 2, 3, 4)
]],
    [[
def foo(a, b, /, c, d):
    pass

result = foo(1, 2, c=3, d=4)
]]
  )

  -- Keyword-only parameters (*)
  test_expand(
    "expands keyword-only arguments (after *)",
    [[
def foo(a, *, b, c):
    pass

result = foo(1, b=2, c=3)
]],
    [[
def foo(a, *, b, c):
    pass

result = foo(a=1, b=2, c=3)
]]
  )

  -- Mixed positional-only and keyword-only
  test_expand(
    "handles mixed positional-only and keyword-only",
    [[
def foo(a, /, b, *, c):
    pass

result = foo(1, 2, c=3)
]],
    [[
def foo(a, /, b, *, c):
    pass

result = foo(1, b=2, c=3)
]]
  )

  -- Default values
  test_expand(
    "expands arguments with default values",
    [[
def foo(a, b=10, c=20):
    pass

result = foo(1, 2, 3)
]],
    [[
def foo(a, b=10, c=20):
    pass

result = foo(a=1, b=2, c=3)
]]
  )

  -- Type hints
  test_expand(
    "expands arguments with type hints",
    [[
def foo(a: int, b: str, c: float):
    pass

result = foo(1, "hello", 3.14)
]],
    [[
def foo(a: int, b: str, c: float):
    pass

result = foo(a=1, b="hello", c=3.14)
]]
  )

  -- Type hints with defaults
  test_expand(
    "expands arguments with type hints and defaults",
    [[
def foo(a: int, b: str = "default", c: float = 0.0):
    pass

result = foo(1, "hello", 3.14)
]],
    [[
def foo(a: int, b: str = "default", c: float = 0.0):
    pass

result = foo(a=1, b="hello", c=3.14)
]]
  )

  -- *args
  test_expand(
    "handles *args in signature",
    [[
def foo(a, *args, b):
    pass

result = foo(1, 2, 3, b=4)
]],
    [[
def foo(a, *args, b):
    pass

result = foo(a=1, 2, 3, b=4)
]]
  )

  -- **kwargs
  test_expand(
    "handles **kwargs in signature",
    [[
def foo(a, b, **kwargs):
    pass

result = foo(1, 2, extra=3)
]],
    [[
def foo(a, b, **kwargs):
    pass

result = foo(a=1, b=2, extra=3)
]]
  )

  -- Nested calls
  test_expand(
    "expands nested function calls",
    [[
def inner(x, y):
    return x + y

def outer(a, b):
    return a * b

result = outer(inner(1, 2), 3)
]],
    [[
def inner(x, y):
    return x + y

def outer(a, b):
    return a * b

result = outer(a=inner(x=1, y=2), b=3)
]]
  )

  -- Method calls
  test_expand(
    "expands method calls",
    [[
class Foo:
    def bar(self, a, b):
        pass

obj = Foo()
result = obj.bar(1, 2)
]],
    [[
class Foo:
    def bar(self, a, b):
        pass

obj = Foo()
result = obj.bar(a=1, b=2)
]],
    "obj.bar"
  )

  -- Complex expressions as arguments
  test_expand(
    "expands with complex expressions as arguments",
    [[
def foo(a, b, c):
    pass

x = 10
result = foo(x + 1, x * 2, x ** 2)
]],
    [[
def foo(a, b, c):
    pass

x = 10
result = foo(a=x + 1, b=x * 2, c=x ** 2)
]]
  )

  -- Multiline call
  test_expand(
    "expands multiline function calls",
    [[
def foo(a, b, c):
    pass

result = foo(
    1,
    2,
    3
)
]],
    [[
def foo(a, b, c):
    pass

result = foo(
    a=1,
    b=2,
    c=3
)
]]
  )

  -- String arguments with special characters
  test_expand(
    "expands with string arguments containing equals",
    [[
def foo(a, b):
    pass

result = foo("x=1", "y=2")
]],
    [[
def foo(a, b):
    pass

result = foo(a="x=1", b="y=2")
]]
  )

  -- Lambda arguments
  test_expand(
    "expands with lambda arguments",
    [[
def foo(a, b):
    pass

result = foo(lambda x: x + 1, lambda y: y * 2)
]],
    [[
def foo(a, b):
    pass

result = foo(a=lambda x: x + 1, b=lambda y: y * 2)
]]
  )

  -- List/dict arguments
  test_expand(
    "expands with list and dict arguments",
    [[
def foo(a, b, c):
    pass

result = foo([1, 2, 3], {"key": "value"}, (1, 2))
]],
    [[
def foo(a, b, c):
    pass

result = foo(a=[1, 2, 3], b={"key": "value"}, c=(1, 2))
]]
  )

  -- Builtin functions (may not have signature help)
  it("handles builtin functions gracefully", function()
    helpers.setup_python_file([[
result = print(1, 2, 3)
]])
    helpers.wait_for_lsp()
    helpers.cursor_on_call("result = ")

    -- Should not error, even if it can't expand
    local ok, err = pcall(kwargs.expand_keywords)
    -- We just want it to not crash
    assert.is_true(ok or err:match("No result") or err:match("No signature"), "Should handle gracefully")
  end)
end)
