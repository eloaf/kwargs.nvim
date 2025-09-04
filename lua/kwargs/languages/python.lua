local utils = require('kwargs.utils')
local parsers = require('nvim-treesitter.parsers')

local M = {}

local ts_query_string = [[
    (call (_)) @call
]]


local python_variable_name_pattern = "[%a_][%w_]*"

--- Find the start and end line of the current selection or line.
---@return integer, integer
local function get_start_and_end_line()
    local start_line = nil
    local end_line = nil

    local mode = vim.api.nvim_get_mode()["mode"]

    -- WARNING: Visual selection problem - the marks are lagging behind by one action.
    -- I guess we somehow need to have as input the mode?

    -- TODO: This is broken
    if mode == 'V' or mode == 'v' then
        -- Visual mode
        start_line = vim.fn.line("'<") - 1
        end_line = vim.fn.line("'>")
        -- -- How to send Esc?
        -- vim.cmd(":yank k")
    elseif mode == 'n' then
        -- start_line = vim.fn.line('.') - 1
        -- end_line = start_line + 1
        start_line = vim.fn.line('.') - 1
        end_line = vim.fn.line('.')
    else
        error("Invalid mode")
    end
    return start_line, end_line
end

-- Traverse treesitter nodes UP until we find the top-most call node
-- starting from the current cursor position and return it.
local function get_top_most_call_node()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local root = tree:root()

    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
    cursor_row = cursor_row - 1 -- Convert to 0-indexed

    local node = root:named_descendant_for_range(cursor_row, cursor_col, cursor_row, cursor_col)

    while node do
        if node:type() == "call" then
            return node
        end
        node = node:parent()
    end

    return nil
end

-- From a given call node, traverse down to find all call nodes under
-- the given node. Return them in a table<integer, TSNode>.
local function get_all_call_nodes(node)
    if node:type() ~= "call" then
        error("Node is not a call node")
    end

    local call_nodes = {}

    local function traverse(n)
        if n:type() == "call" then
            call_nodes[#call_nodes + 1] = n
        end
        for child, _ in n:iter_children() do
            traverse(child)
        end
    end

    traverse(node)
    return call_nodes
end

---@return table<integer, TSNode>
local function get_call_nodes()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("python", ts_query_string)

    local start_line, end_line = get_start_and_end_line()

    local top_most_call_node = get_top_most_call_node()
    if top_most_call_node == nil then
        error("No call node found at cursor")
    end
    local call_nodes = {}
    for _, node in ipairs(get_all_call_nodes(top_most_call_node)) do
        call_nodes[#call_nodes + 1] = node
    end
    return call_nodes

    -- --- @type table<integer, TSNode>
    -- local call_nodes = {}
    -- for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
    --     local capture_name = query.captures[id]
    --
    --     if capture_name == 'arg' then
    --         print("Found argument node: " .. vim.treesitter.get_node_text(node, 0))
    --     end
    --
    --     if capture_name == "call" then
    --         call_nodes[#call_nodes + 1] = node
    --     end
    -- end
    --
    -- return call_nodes
end

--- Return the argument list of a call node.
---@param call_node TSNode
local function get_argument_list(call_node)
    if call_node:type() ~= "call" then
        print(call_node:type())
        error("Node is not a call node")
    end
    local argument_list_node = utils.find_first_node_of_type_bfs(call_node, "argument_list")
    if argument_list_node == nil then
        error("No argument list node found")
    end
    return argument_list_node
end

--- @param call_node TSNode
--- @return table
local function make_lsp_params(call_node)
    local argument_list_node = utils.find_first_node_of_type_bfs(call_node, "argument_list")

    if argument_list_node == nil then
        error("No arguments node found")
    end

    -- Extract the position from arguments_node
    local start_row, start_col = argument_list_node:start()

    -- Create params using the position
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = { line = start_row, character = start_col }
    }
    return params
end



--- @class ArgumentInfo
--- @field name string The name of the argument.
--- @field type string|nil The type hint of the argument, if any.
--- @field default string|nil The default value of the argument, if any.
--- @field positional_only boolean Whether the argument is positional only.
--- @field keyword_only boolean Whether the argument is keyword only.

--- Retrieves a function's signature and reformats it into a table of tables.
--- @param call_node TSNode: The node representing the function call.
--- @return table<integer, ArgumentInfo>
local function get_function_signature(call_node)
    if call_node:type() ~= "call" then
        error("Node is not a call node")
    end

    local params = make_lsp_params(call_node)

    -- WARNING: Not sure I understand this...
    params.position.character = params.position.character + 1
    -- params.position.line = params.position.line + 1

    local result = vim.lsp.buf_request_sync(0, "textDocument/signatureHelp", params, 10000)

    if result == nil then
        error("No result returned!")
    end

    local key = next(result)

    if not (result and result[key] and result[key].result and result[key].result.signatures) then
        error("No signature help available!")
    end

    local signature = result[key].result.signatures[1]
    local label = signature.label
    local parameters = signature.parameters

    local arg_texts = {}
    for _, parameter in ipairs(parameters) do
        local start_end = parameter.label
        local arg_text = string.sub(label, 1 + start_end[1], start_end[2])
        arg_texts[#arg_texts + 1] = arg_text
    end

    -- print("Arg texts: " .. vim.inspect(arg_texts))

    local arg_data = {}

    local keyword_only = false

    for _, arg_text in ipairs(arg_texts) do
        -- print("Arg text: " .. arg_text)

        if arg_text == "/" then
            for i = #arg_data, 1, -1 do
                arg_data[i].positional_only = true
            end
            goto continue
        elseif arg_text == "*" then
            keyword_only = true
            goto continue
        end

        local column_start, _ = string.find(arg_text, ":")
        local equals_start, _ = string.find(arg_text, "=")

        local type_hint = nil
        local default_value = nil
        local arg_name = nil

        if column_start == nil and equals_start == nil then
            -- No type hint and no default value
            -- a
            arg_name = arg_text
        elseif column_start == nil and equals_start ~= nil then
            -- No type hint but has a default value
            -- a = 1
            arg_name = string.match(arg_text, "([%a%s_]+)")
            default_value = string.match(arg_text, "[%a%s_]+ ?= ?(.+)")
        elseif column_start ~= nil and equals_start == nil then
            -- A type hint but no default value
            -- a: int
            arg_name = string.match(arg_text, "([%a%s_]+)")
            type_hint = string.match(arg_text, "[%a%s_]+ ?: ?([^=])+")
        elseif column_start ~= nil and equals_start ~= nil then
            -- A type hint and a default value
            -- a: int = 1
            arg_name = string.match(arg_text, "([%a%s_]+)")
            type_hint = string.match(arg_text, "[%a%s_]+ ?: ?([^=])+")
            default_value = string.match(arg_text, ".+ ?= ?(.+)")
        end

        local index = #arg_data + 1
        arg_data[#arg_data + 1] = {
            index = index,
            name = arg_name,
            type = type_hint,
            default = default_value,
            positional_only = false,
            keyword_only = keyword_only,
        }

        ::continue::
    end

    return arg_data
end

--- Returns a table containing the positional and keyword arguments from the call node.
--- @param call_node TSNode
--- @return table
local function get_call_values(call_node)
    if call_node:type() ~= "call" then
        error("Node is not a call node")
    end

    local argument_list_node = utils.find_first_node_of_type_bfs(call_node, "argument_list")

    if argument_list_node == nil then
        error("No argument list node found")
    end

    local discarded_node_types = {
        [","] = true,
        ["("] = true,
        [")"] = true,
    }

    local result = {}

    for child_node, _ in argument_list_node:iter_children() do
        if discarded_node_types[child_node:type()] == true then
            goto continue
        end

        local text = vim.treesitter.get_node_text(child_node, 0)

        local entry = { name = nil, value = text, node = child_node }
        if child_node:type() == "keyword_argument" then
            local pos = string.find(text, "=")
            entry.name = string.sub(text, 1, pos - 1)
            entry.value = string.sub(text, pos + 1)
        end
        result[#result + 1] = entry

        ::continue::
    end

    return result
end

---@class ArgumentData
---@field name string
---@field value string
---@field node TSNode
---@field positional_only boolean
---@field keyword_only boolean
---@field default string|nil

--- Processes a function call node to align its arguments with the function signature.
---@param call_node TSNode The node representing the function call.
---@return table<integer, ArgumentData>
local function process_call_code(call_node)
    local signature = get_function_signature(call_node)
    local call_values = get_call_values(call_node)

    --- @type table<integer, ArgumentData>
    local positional_call_values = vim.tbl_filter(function(x) return x["name"] == nil end, call_values)

    --- @type table<integer, ArgumentData>
    local keyword_call_values = vim.tbl_filter(function(x) return x["name"] ~= nil end, call_values)

    local aligned = {}
    for j, call_value in ipairs(positional_call_values) do
        local argument_data = signature[j]
        aligned[#aligned + 1] = {
            name = argument_data.name,
            value = call_value["value"],
            node = call_value["node"],
            positional_only = argument_data.positional_only,
            keyword_only = argument_data.keyword_only,
            default = argument_data.default,
        }
    end

    for _, call_value in ipairs(keyword_call_values) do
        -- TODO: Move to function
        -- find the arg in the signature
        local index = nil
        for k, signature_arg in ipairs(signature) do
            if signature_arg.name == call_value["name"] then
                index = k
                break
            end
        end

        if index == nil then
            error("Argument not found in signature")
        end

        aligned[#aligned + 1] = {
            name = call_value["name"],
            value = call_value["value"],
            node = call_value["node"],
            index = index,
            positional_only = signature[index].positional_only,
            keyword_only = signature[index].keyword_only,
            default = signature[index].default,
        }
    end

    return aligned
end


-- NOTE: What to do when the LSP is not available?
-- Here we could fallback to just searching the current file? How does `K` do it?
-- Copilot:
-- If the LSP is not available, you can use Neovim's built-in `:help` command to get the documentation for a keyword.
-- You can capture the output of the `:help` command using the `vim.fn.execute` function.
-- Here's an example of how you can do this in Lua:
-- ```lua
-- local function get_help_contents(keyword)
--     -- Capture the output of the :help command
--     local help_output = vim.fn.execute('help ' .. keyword)
--     return help_output
-- end
-- Example usage
-- local keyword = vim.fn.expand('<cword>') -- Get the word under the cursor
-- local help_text = get_help_contents(keyword)
-- if help_text then
--     print(help_text)
-- end
-- ```
-- This function captures the output of the `:help` command for the given keyword and returns it as a string. You can then analyze the `help_text` variable as needed.


-- --- Inspects a table of TSNode
-- ---@param nodes table<TSNode>
-- local function inspect_nodes(nodes)
--     for i, node in ipairs(nodes) do
--         local text = vim.treesitter.get_node_text(node, 0)
--         print("Node " .. i .. ": " .. text)
--     end
-- end


---@class Edit
---@field row_start integer @start row (0-index)
---@field col_start integer @start col (bytes)
---@field row_end integer   @end row (0-index); for pure insert, sr=er
---@field col_end integer   @end col (bytes); for pure insert, sc=ec
---@field text string[]        @replacement lines; for pure insert, sr=er & sc=ec


---Expands the keyword arguments in the current line.
M.expand_keywords = function()
    if not utils.lsp_supports_signature_help() then
        error("No LSP client supports signature help")
    end

    -- local parser = parsers.get_parser()
    -- local tree = parser:parse()[1]
    -- local query = vim.treesitter.query.parse("python", ts_query_string)
    --
    -- -- TODO: Doesn't work with visual selection - fix it.
    -- local start_line, end_line = get_start_and_end_line()

    local call_nodes = get_call_nodes()

    ---@type table<integer, Edit>
    local edits = {}

    -- for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
    --     local capture_name = query.captures[id]

    for i = 1, #call_nodes do
        -- if capture_name ~= "call" then
        --     error("Capture is not a call node: " .. capture_name)
        -- end

        local call_node = call_nodes[i]
        local argument_list_node = get_argument_list(call_node)

        -- Collect all the argument nodes in the argument_list
        local arguments = {}
        for child_node, _ in argument_list_node:iter_children() do
            if child_node:type() ~= "," and child_node:type() ~= "(" and child_node:type() ~= ")" then
                arguments[#arguments + 1] = child_node
            end
        end

        for _, data in ipairs(process_call_code(call_node)) do
            -- Positional only arguments cannot be expanded
            if data["positional_only"] == true then
                goto continue
            end

            -- Check if the keyword is already present
            local node_text = vim.treesitter.get_node_text(data.node, 0)
            if string.sub(node_text, 1, #data.name + 1) == data.name .. "=" then
                goto continue
            end

            -- Set up the edit for this argument
            local row_start, col_start, _, _ = data.node:range()
            local edit = {
                row_start = row_start,
                col_start = col_start,
                text = { data.name .. "=" }, -- Only insert the keyword and equals sign
            }
            edits[#edits + 1] = edit

            ::continue::
        end
    end

    -- Finally, sort the edits in reverse order by row_start and col_start
    table.sort(edits, function(a, b)
        if a.row_start == b.row_start then
            return a.col_start > b.col_start
        end
        return a.row_start > b.row_start
    end)

    -- Apply the edits (they are already sorted in reverse order)
    for _, edit in ipairs(edits) do
        vim.api.nvim_buf_set_text(0, edit.row_start, edit.col_start, edit.row_start, edit.col_start, edit.text)
    end
end


M.contract_keywords = function()
    if not utils.lsp_supports_signature_help() then
        return
    end

    local call_nodes = get_call_nodes()
    ---@type table<integer, Edit>
    local edits = {}

    for i = 1, #call_nodes do
        local call_node = call_nodes[i]
        local aligned = process_call_code(call_node)

        for j = 1, #aligned do
            local data = aligned[j]

            -- Skip contraction of the keyword only arguments
            if data["keyword_only"] == true then
                goto continue
            end

            -- Positional only arguments cannot/should not be contracted
            if data["positional_only"] == true then
                goto continue
            end

            -- If the current argument does not have a keyword, we cannot contract it
            if data["name"] == nil then
                goto continue
            end

            -- Get the node's text
            local node_text = vim.treesitter.get_node_text(data.node, 0)

            -- Check if the value starts with a python variable name pattern
            -- plus an equals sign
            -- print("Checking value: " .. data["value"])
            if not string.match(node_text, python_variable_name_pattern .. "%s*=") then
                goto continue
            end

            -- TODO: Copilot fucked up here. Re-do

            ---@type TSNode
            local node = data["node"]
            local row_start, col_start, _, _ = node:range()
            -- print("Contracting argument: " .. data["name"] .. " at " .. row_start .. ":" .. col_start)
            -- TODO: Multiline edits don't work here.
            edits[#edits + 1] = {
                row_start = row_start,
                col_start = col_start,
                row_end = row_start,
                col_end = col_start + #data["name"] + 1, -- +1 for the equals sign
                text = { "" },                           -- Delete the keyword and equals sign
            }

            ::continue::
        end
    end

    -- Sort edits in reverse order
    table.sort(edits, function(a, b)
        if a.row_start == b.row_start then
            return a.col_start > b.col_start
        end
        return a.row_start > b.row_start
    end)

    -- Apply edits
    for _, edit in ipairs(edits) do
        local line = vim.api.nvim_buf_get_lines(0, edit.row_end, edit.row_end + 1, false)[1] or ""
        local line_length = #line
        local end_col = math.min(edit.col_end, line_length)
        -- print("Applying edit: " .. vim.inspect(edit))
        vim.api.nvim_buf_set_text(0, edit.row_start, edit.col_start, edit.row_end, end_col, edit.text)
        -- vim.api.nvim_buf_set_text(0, edit.row_start, edit.col_start, edit.row_end, edit.col_end, edit.text)
    end
end


-- -- Actually this is harder because we need to insert new text, not just modify existing nodes!
-- M.insert_defaults = function()
--     if not lsp_supports_signature_help() then
--         return
--     end
--     local call_nodes = get_call_nodes()
--     for i = #call_nodes, 1, -1 do
--         local call_node = call_nodes[i]
--         local aligned = process_call_code(call_node)
--         -- here we can iterate backwords over the aligned arguments and insert them into the buffer
--         for j = #aligned, 1, -1 do
--             local data = aligned[j]
--             local default = data["default"]
--             if default == nil then
--                 goto continue
--             end
--             ---@type TSNode
--             local node = data["node"]
--             local row_start, col_start, row_end, col_end = node:range()
--             print("default: " .. default)
--             -- Actually if its a keyword only argument we should insert default default as a kwarg
--             local replacement = default
--             if data["keyword_only"] == true then
--                 replacement = data["name"] .. "=" .. replacement
--             end
--             vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { replacement })
--             ::continue::
--         end
--     end
-- end

return M

-- TODO: Fails with kwargs: try:
-- return pydantic.create_model(
--     name,
--     __base__=Extra,
--     **fields,
-- )
