local M = {}

M.bufnr = nil
M.test_file = nil

--- Create a temporary Python file and open it
---@param content string
---@return string filepath
function M.setup_python_file(content)
  -- Create a temp file so LSP can analyze it properly
  local tmp = os.tmpname() .. ".py"
  local f = io.open(tmp, "w")
  f:write(content)
  f:close()

  M.test_file = tmp

  -- Open the file in a buffer
  vim.cmd("edit " .. tmp)
  M.bufnr = vim.api.nvim_get_current_buf()

  return tmp
end

--- Clean up test buffer and file
function M.teardown()
  if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
    -- Stop LSP clients
    local clients = vim.lsp.get_clients({ bufnr = M.bufnr })
    for _, client in ipairs(clients) do
      client.stop()
    end
    vim.api.nvim_buf_delete(M.bufnr, { force = true })
  end
  if M.test_file then
    os.remove(M.test_file)
    M.test_file = nil
  end
  M.bufnr = nil
end

--- Wait for LSP to attach and be ready
---@param timeout_ms? integer
---@return boolean
function M.wait_for_lsp(timeout_ms)
  timeout_ms = timeout_ms or 10000

  local attached = vim.wait(timeout_ms, function()
    local clients = vim.lsp.get_clients({ bufnr = M.bufnr })
    return #clients > 0
  end, 100)

  if not attached then
    return false
  end

  -- Wait a bit more for LSP to fully initialize
  vim.wait(500, function() return false end)

  -- Verify signature help is available
  local ready = vim.wait(timeout_ms, function()
    local clients = vim.lsp.get_clients({ bufnr = M.bufnr })
    for _, client in ipairs(clients) do
      if client.server_capabilities.signatureHelpProvider then
        return true
      end
    end
    return false
  end, 100)

  return ready
end

--- Get buffer content as string (with trailing newline for consistency)
---@return string
function M.get_buffer_content()
  local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  return table.concat(lines, "\n") .. "\n"
end

--- Set cursor position (1-indexed line, 0-indexed col)
---@param line integer
---@param col integer
function M.set_cursor(line, col)
  vim.api.nvim_win_set_cursor(0, { line, col })
end

--- Get the line containing a pattern
---@param pattern string
---@return integer? line_number (1-indexed)
function M.find_line(pattern)
  local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      return i
    end
  end
  return nil
end

--- Position cursor on a function call matching pattern
--- Positions cursor inside the parentheses of the call
---@param pattern string
---@return boolean
function M.cursor_on_call(pattern)
  local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      -- Find the opening parenthesis to position cursor inside the call
      local paren_pos = line:find("%(")
      if paren_pos then
        M.set_cursor(i, paren_pos) -- Position just after the (
        return true
      else
        M.set_cursor(i, 0)
        return true
      end
    end
  end
  return false
end

return M
