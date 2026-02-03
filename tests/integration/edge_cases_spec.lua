local helpers = require("tests.helpers")
local kwargs = require("kwargs")

describe("edge cases", function()
  after_each(function()
    helpers.teardown()
  end)

  describe("exotic signatures", function()
    it("handles self parameter in methods", function()
      helpers.setup_python_file([[
class Calculator:
    def add(self, a, b, c=0):
        return a + b + c

calc = Calculator()
result = calc.add(1, 2)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("calc.add")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("calc.add%(a=1, b=2%)") ~= nil)
    end)

    it("handles cls parameter in classmethods", function()
      helpers.setup_python_file([[
class Factory:
    @classmethod
    def create(cls, name, value):
        pass

result = Factory.create("test", 42)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("Factory.create")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match('Factory.create%(name="test", value=42%)') ~= nil)
    end)

    it("handles staticmethod (no self/cls)", function()
      helpers.setup_python_file([[
class Utils:
    @staticmethod
    def helper(a, b):
        return a + b

result = Utils.helper(1, 2)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("Utils.helper")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("Utils.helper%(a=1, b=2%)") ~= nil)
    end)

    it("handles complex default values", function()
      helpers.setup_python_file([[
def foo(a, b=None, c=[], d={}):
    pass

result = foo(1, 2, 3, 4)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("foo%(a=1, b=2, c=3, d=4%)") ~= nil)
    end)

    it("handles Union type hints", function()
      helpers.setup_python_file([[
from typing import Union

def foo(a: Union[int, str], b: Union[list, tuple]):
    pass

result = foo(1, [2, 3])
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("foo%(a=1, b=%[2, 3%]%)") ~= nil)
    end)

    it("handles Optional type hints", function()
      helpers.setup_python_file([[
from typing import Optional

def foo(a: int, b: Optional[str] = None):
    pass

result = foo(1, "test")
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match('foo%(a=1, b="test"%)') ~= nil)
    end)

    it("handles Callable type hints", function()
      helpers.setup_python_file([[
from typing import Callable

def foo(func: Callable[[int], int], value: int):
    return func(value)

result = foo(lambda x: x * 2, 5)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("foo%(func=lambda x: x %* 2, value=5%)") ~= nil)
    end)
  end)

  describe("pydantic and dataclass patterns", function()
    it("handles dataclass __init__", function()
      helpers.setup_python_file([[
from dataclasses import dataclass

@dataclass
class Point:
    x: int
    y: int
    z: int = 0

result = Point(1, 2, 3)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("Point%(x=1, y=2, z=3%)") ~= nil)
    end)
  end)

  describe("problematic patterns from NOTES.md", function()
    it("handles **kwargs splat in call", function()
      helpers.setup_python_file([[
def create_model(name, base, **fields):
    pass

result = create_model("MyModel", object, field1=int, field2=str)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      -- Should expand name and base, leave **kwargs args alone
      assert.is_true(content:match('create_model%(name="MyModel", base=object') ~= nil)
    end)

    it("handles *args splat in call", function()
      helpers.setup_python_file([[
def variadic(first, *rest):
    pass

result = variadic(1, 2, 3, 4)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      -- Should expand first, rest stay positional
      assert.is_true(content:match("variadic%(first=1, 2, 3, 4%)") ~= nil)
    end)

    it("handles mixed / and * in same signature", function()
      helpers.setup_python_file([[
def complex_sig(pos_only, /, normal, *, kw_only):
    pass

result = complex_sig(1, 2, kw_only=3)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      -- pos_only stays positional, normal gets expanded, kw_only stays keyword
      assert.is_true(content:match("complex_sig%(1, normal=2, kw_only=3%)") ~= nil)
    end)
  end)

  describe("whitespace and formatting", function()
    it("preserves indentation in multiline calls", function()
      helpers.setup_python_file([[
def foo(a, b, c):
    pass

result = foo(
        1,
        2,
        3,
    )
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      -- Check that indentation is preserved
      assert.is_true(content:match("        a=1") ~= nil)
    end)

    it("handles trailing comma", function()
      helpers.setup_python_file([[
def foo(a, b, c):
    pass

result = foo(1, 2, 3,)
]])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.is_true(content:match("foo%(a=1, b=2, c=3,%)") ~= nil)
    end)
  end)

  describe("round-trip consistency", function()
    it("expand then contract returns to original (simple case)", function()
      local original = [[
def foo(a, b, c):
    pass

result = foo(1, 2, 3)
]]
      helpers.setup_python_file(original)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")

      -- Expand
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      -- Contract
      helpers.cursor_on_call("result = ")
      kwargs.contract_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(original, content)
    end)

    it("contract then expand returns to original (simple case)", function()
      local original = [[
def foo(a, b, c):
    pass

result = foo(a=1, b=2, c=3)
]]
      helpers.setup_python_file(original)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready)

      helpers.cursor_on_call("result = ")

      -- Contract
      kwargs.contract_keywords()
      vim.wait(50, function() return false end)

      -- Expand
      helpers.cursor_on_call("result = ")
      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(original, content)
    end)
  end)
end)
