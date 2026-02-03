local helpers = require("tests.helpers")
local kwargs = require("kwargs")

describe("nested generic dataclass calls", function()
  after_each(function()
    helpers.teardown()
  end)

  local function test_expand(description, input, expected, call_pattern)
    it(description .. " (expand)", function()
      helpers.setup_python_file(input)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      local found = helpers.cursor_on_call(call_pattern or "return ")
      assert.is_true(found, "Should find call pattern")

      kwargs.expand_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(expected, content)
    end)
  end

  local function test_contract(description, input, expected, call_pattern)
    it(description .. " (contract)", function()
      helpers.setup_python_file(input)
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      local found = helpers.cursor_on_call(call_pattern or "return ")
      assert.is_true(found, "Should find call pattern")

      kwargs.contract_keywords()
      vim.wait(50, function() return false end)

      local content = helpers.get_buffer_content()
      assert.equals(expected, content)
    end)
  end

  describe("Result wrapping dataclass", function()
    test_expand(
      "handles Result wrapping dataclass with kwargs",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    return Result(
        _IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
        )
    )
]=]
    )

    test_contract(
      "handles Result wrapping dataclass - contract outer",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    return Result(
        _IntermediateResults(
            body_text,
            abstract_text,
        )
    )
]=]
    )
  end)

  describe("complex dataclass with many fields", function()
    test_expand(
      "handles dataclass with 6 fields inside Result",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text,
            abstract_text,
            summary,
            extraction_id_to_answer,
            citation_to_source,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=]
    )

    test_contract(
      "contract dataclass with 6 kwargs inside Result - all contractable kwargs should contract",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text,
            abstract_text,
            summary,
            extraction_id_to_answer,
            citation_to_source,
        )
    )
]=]
    )
  end)

  describe("debugging signature retrieval", function()
    it("shows what pyright returns for nested Result(dataclass()) calls", function()
      helpers.setup_python_file([=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    return Result(
        _IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
        )
    )
]=])
      local ready = helpers.wait_for_lsp()
      assert.is_true(ready, "LSP should be ready")

      helpers.cursor_on_call("return ")

      -- Get cursor position
      local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
      print("\n=== DEBUG: Cursor position: row=" .. cursor_row .. " col=" .. cursor_col)

      -- Try to get signature at different positions
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      -- Find the Result( line
      for i, line in ipairs(lines) do
        if line:match("return Result") then
          print("=== Line " .. i .. ": " .. line)
          -- Try signature at position after Result(
          local result_pos = line:find("Result%(")
          if result_pos then
            local params = {
              textDocument = vim.lsp.util.make_text_document_params(),
              position = { line = i - 1, character = result_pos }
            }
            local result = vim.lsp.buf_request_sync(0, "textDocument/signatureHelp", params, 10000)
            if result then
              local key = next(result)
              if result[key] and result[key].result and result[key].result.signatures then
                local sig = result[key].result.signatures[1]
                print("=== RESULT SIGNATURE ===")
                print("Label: " .. sig.label)
                print("Params: " .. #sig.parameters)
                for j, param in ipairs(sig.parameters) do
                  local param_text = sig.label:sub(param.label[1] + 1, param.label[2])
                  print("  Param " .. j .. ": '" .. param_text .. "'")
                end
              end
            end
          end
        elseif line:match("_IntermediateResults") and line:match("%(") then
          print("=== Line " .. i .. ": " .. line)
          local inter_pos = line:find("_IntermediateResults%(")
          if inter_pos then
            local params = {
              textDocument = vim.lsp.util.make_text_document_params(),
              position = { line = i - 1, character = inter_pos + 20 }
            }
            local result = vim.lsp.buf_request_sync(0, "textDocument/signatureHelp", params, 10000)
            if result then
              local key = next(result)
              if result[key] and result[key].result and result[key].result.signatures then
                local sig = result[key].result.signatures[1]
                print("=== _INTERMEDIATERESULTS SIGNATURE ===")
                print("Label: " .. sig.label)
                print("Params: " .. #sig.parameters)
                for j, param in ipairs(sig.parameters) do
                  local param_text = sig.label:sub(param.label[1] + 1, param.label[2])
                  print("  Param " .. j .. ": '" .. param_text .. "'")
                end
              end
            end
          end
        end
      end
    end)
  end)

  -- REGRESSION TEST: Contract should NOT corrupt dataclass name when outer call is positional
  -- and inner call has keyword arguments
  describe("regression: outer positional + inner kwargs", function()
    test_contract(
      "does NOT corrupt dataclass name when outer is positional and inner has kwargs",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType]):
    pass

class Result(Check[_ResultType]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "summary"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text,
            abstract_text,
            summary,
            extraction_id_to_answer,
            citation_to_source,
        )
    )
]=]
    )
  end)

  -- User's exact error case: Check[_ResultType, Any] not just Check[_ResultType]
  describe("user reported case with Check[_ResultType, Any]", function()
    test_expand(
      "handles Result(Check[_ResultType, Any]) with dataclass",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType, Any]):
    pass

class Result(Check[_ResultType, Any]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "test"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType, Any]):
    pass

class Result(Check[_ResultType, Any]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "test"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=]
    )

    -- Test with positional args being expanded (user's actual use case)
    test_expand(
      "expands positional args in dataclass nested in Result",
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType, Any]):
    pass

class Result(Check[_ResultType, Any]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "test"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        _IntermediateResults(
            body_text,
            abstract_text,
            summary,
            extraction_id_to_answer,
            citation_to_source,
        )
    )
]=],
      [=[
from typing import Generic, TypeVar, Any
from dataclasses import dataclass

_ResultType = TypeVar('_ResultType')

class Check(Generic[_ResultType, Any]):
    pass

class Result(Check[_ResultType, Any]):
    def __init__(self, value: _ResultType):
        self.value = value

@dataclass
class _IntermediateResults:
    body_text: str
    abstract_text: str
    summary: str
    extraction_id_to_answer: dict
    citation_to_source: dict

def process() -> Result[_IntermediateResults]:
    body_text = "hello"
    abstract_text = "world"
    summary = "test"
    extraction_id_to_answer = {}
    citation_to_source = {}
    return Result(
        value=_IntermediateResults(
            body_text=body_text,
            abstract_text=abstract_text,
            summary=summary,
            extraction_id_to_answer=extraction_id_to_answer,
            citation_to_source=citation_to_source,
        )
    )
]=]
    )
  end)
end)
