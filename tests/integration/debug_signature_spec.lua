local helpers = require("tests.helpers")

describe("debug complex signatures", function()
  after_each(function()
    helpers.teardown()
  end)

  it("shows what pyright returns for CoroutineType signature", function()
    helpers.setup_python_file([=[
from typing import Any, Literal
from collections.abc import CoroutineType

class Block:
    pass

class Transport:
    pass

def rerank_quotes_with_cross_encoder(
    report: list[Block],
    transport: Transport,
    part: Literal['abstract', 'body']
) -> CoroutineType[Any, Any, list[Block]]:
    pass

result = rerank_quotes_with_cross_encoder([], Transport(), 'abstract')
]=])
    local ready = helpers.wait_for_lsp()
    assert.is_true(ready, "LSP should be ready")

    helpers.cursor_on_call("result = ")

    -- Get signature help at this position
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local params = {
      textDocument = vim.lsp.util.make_text_document_params(),
      position = { line = cursor_row - 1, character = cursor_col + 1 }
    }

    local result = vim.lsp.buf_request_sync(0, "textDocument/signatureHelp", params, 10000)

    if result then
      local key = next(result)
      if result[key] and result[key].result and result[key].result.signatures then
        local sig = result[key].result.signatures[1]
        print("=== SIGNATURE DEBUG ===")
        print("Label: " .. sig.label)
        print("Number of parameters: " .. #sig.parameters)
        for i, param in ipairs(sig.parameters) do
          local param_text = sig.label:sub(param.label[1] + 1, param.label[2])
          print("  Param " .. i .. ": '" .. param_text .. "'")
        end
        print("=======================")

        -- Should have 3 parameters
        assert.equals(3, #sig.parameters, "Expected 3 parameters")
      else
        print("No signature returned!")
        assert.is_true(false, "No signature")
      end
    end
  end)
end)
