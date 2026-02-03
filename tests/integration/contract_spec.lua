local helpers = require("tests.helpers")
local kwargs = require("kwargs")

describe("contract_keywords", function()
  after_each(function()
    helpers.teardown()
  end)

  local function test_contract(description, input, expected, call_pattern)
    it(description, function()
      helpers.setup_python_file(input)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      -- Position cursor on the call
      local found = helpers.cursor_on_call(call_pattern or "result = ")
      assert.is_true(found, "Should find call pattern")

      -- Run contract
      kwargs.contract_keywords()

      -- Small wait for buffer update
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(expected, content)
    end)
  end

  -- Basic cases
  test_contract(
    "contracts simple keyword arguments",
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]]
  )

  test_contract(
    "contracts partial keyword arguments",
    [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]]
  )

  test_contract(
    "does nothing to already positional arguments",
    [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]],
    [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]]
  )

  -- Positional-only (should stay positional)
  test_contract(
    "keeps positional-only arguments positional",
    [[
def foo(a, b, /, c, d):
    pass

result = foo(1, 2, c=3, d=4)
]],
    [[
def foo(a, b, /, c, d):
    pass

result = foo(1, 2, 3, 4)
]]
  )

  -- Keyword-only (should NOT contract)
  test_contract(
    "does NOT contract keyword-only arguments",
    [[
def foo(a, *, b, c):
    pass

result = foo(a=1, b=2, c=3)
]],
    [[
def foo(a, *, b, c):
    pass

result = foo(1, b=2, c=3)
]]
  )

  -- Mixed positional-only and keyword-only
  test_contract(
    "handles mixed positional-only and keyword-only",
    [[
def foo(a, /, b, *, c):
    pass

result = foo(1, b=2, c=3)
]],
    [[
def foo(a, /, b, *, c):
    pass

result = foo(1, 2, c=3)
]]
  )

  -- With defaults
  test_contract(
    "contracts arguments with defaults",
    [[
def foo(a, b=10, c=20):
    pass

result = foo(a=1, b=2, c=3)
]],
    [[
def foo(a, b=10, c=20):
    pass

result = foo(1, 2, 3)
]]
  )

  -- Type hints
  test_contract(
    "contracts arguments with type hints",
    [[
def foo(a: int, b: str, c: float):
    pass

result = foo(a=1, b="hello", c=3.14)
]],
    [[
def foo(a: int, b: str, c: float):
    pass

result = foo(1, "hello", 3.14)
]]
  )

  -- Nested calls
  test_contract(
    "contracts nested function calls",
    [[
def inner(x, y):
    return x + y

def outer(a, b):
    return a * b

result = outer(a=inner(x=1, y=2), b=3)
]],
    [[
def inner(x, y):
    return x + y

def outer(a, b):
    return a * b

result = outer(inner(1, 2), 3)
]]
  )

  -- Method calls
  test_contract(
    "contracts method calls",
    [[
class Foo:
    def bar(self, a, b):
        pass

obj = Foo()
result = obj.bar(a=1, b=2)
]],
    [[
class Foo:
    def bar(self, a, b):
        pass

obj = Foo()
result = obj.bar(1, 2)
]],
    "obj.bar"
  )

  -- Multiline call
  test_contract(
    "contracts multiline function calls",
    [[
def foo(a, b, c):
    pass

result = foo(
    a=1,
    b=2,
    c=3
)
]],
    [[
def foo(a, b, c):
    pass

result = foo(
    1,
    2,
    3
)
]]
  )

  -- Complex expressions
  test_contract(
    "contracts with complex expressions",
    [[
def foo(a, b, c):
    pass

x = 10
result = foo(a=x + 1, b=x * 2, c=x ** 2)
]],
    [[
def foo(a, b, c):
    pass

x = 10
result = foo(x + 1, x * 2, x ** 2)
]]
  )

  -- Out of order kwargs (edge case - may need reordering)
  test_contract(
    "contracts out-of-order kwargs",
    [[
def foo(a, b, c):
    pass

result = foo(c=3, a=1, b=2)
]],
    [[
def foo(a, b, c):
    pass

result = foo(3, 1, 2)
]]
  )

  -- **kwargs pass-through should not be contracted
  test_contract(
    "does not contract **kwargs splat",
    [[
def foo(a, b, **kwargs):
    pass

d = {"extra": 1}
result = foo(a=1, b=2, **d)
]],
    [[
def foo(a, b, **kwargs):
    pass

d = {"extra": 1}
result = foo(1, 2, **d)
]]
  )

  -- Lambda in argument value
  test_contract(
    "contracts with lambda arguments",
    [[
def foo(a, b):
    pass

result = foo(a=lambda x: x + 1, b=lambda y: y * 2)
]],
    [[
def foo(a, b):
    pass

result = foo(lambda x: x + 1, lambda y: y * 2)
]]
  )
end)
