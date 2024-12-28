local utils = require('kwargs.utils')
local parsers = require('nvim-treesitter.parsers')

local debug = false

local M = {}

local ts_query_string = [[
    (
      (call
        function: [
          (identifier) @identifier
          (attribute
            object: (_)
            attribute: (identifier)
          )
        ]
        arguments:
          (argument_list
            (_)* @arg
          ) @list
      ) @call
    )
]]


---@return table<integer, TSNode>
local function get_call_nodes()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("python", ts_query_string)

    -- local start_line, end_line
    local start_line = nil
    local end_line = nil

    local mode = vim.api.nvim_get_mode()["mode"]

    -- print(mode)

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
        -- Normal mode
        start_line = vim.fn.line('.') - 1
        end_line = start_line + 1
    else
        error("Invalid mode")
    end

    -- print("Start line: " .. start_line)
    -- print("End line: " .. end_line)

    --- @type table<integer, TSNode>
    local call_nodes = {}
    for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
        local capture_name = query.captures[id]
        if capture_name == "call" then
            call_nodes[#call_nodes + 1] = node
        end
    end

    return call_nodes
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


--- TODO
--- @param call_node TSNode
--- @return table
local function get_params_from_call_node(call_node)
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


--- Retrieves a function's signature and reformats it into a table of tables.
--- @param call_node TSNode: The node representing the function call.
--- @return table: A table containing the function's arguments with their details.
--- Each argument is represented as a table with the following fields:
--- - name (string): The name of the argument.
--- - type (string|nil): The type hint of the argument, if any.
--- - default (string|nil): The default value of the argument, if any.
--- - positional_only (boolean): Whether the argument is positional only.
--- - keyword_only (boolean): Whether the argument is keyword only.
local function get_function_signature(call_node)
    if call_node:type() ~= "call" then
        error("Node is not a call node")
    end

    local params = get_params_from_call_node(call_node)

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

--- Returns the first LSP client that supports signature help.
---@return vim.lsp.Client?
local function lsp_supports_signature_help()
    -- Ensure the LSP client is attached
    local clients = vim.lsp.get_clients()

    local clients_with_signature_help = {}
    for _, client in ipairs(clients) do
        if client.server_capabilities.signatureHelpProvider then
            clients_with_signature_help[#clients_with_signature_help + 1] = client
        end
    end

    utils.maybe_print("Clients" .. #clients .. "Clients with signatureHelp" .. #clients_with_signature_help, debug)

    if #clients_with_signature_help == 0 then
        utils.maybe_print("No LSP client attached", debug)
        return nil
    end

    utils.maybe_print("LSP server supports signatureHelp", debug)

    return clients_with_signature_help[1]
end

--- Processes a function call node and aligns the call values with the function signature.
-- @param call_node The AST node representing the function call.
-- @return A table containing aligned call values with their corresponding signature details.
-- Each entry in the table includes:
--   - name: The name of the argument.
--   - value: The value passed to the argument.
--   - node: The AST node of the call value.
--   - index: The index of the argument in the function signature.
--   - positional_only: Boolean indicating if the argument is positional only.
--   - keyword_only: Boolean indicating if the argument is keyword only.
--   - default: The default value of the argument, if any.
local function process_call_code(call_node)
    local signature = get_function_signature(call_node)
    local call_values = get_call_values(call_node)

    local positional_call_values = vim.tbl_filter(function(x) return x["name"] == nil end, call_values)
    local keyword_call_values = vim.tbl_filter(function(x) return x["name"] ~= nil end, call_values)

    local aligned = {}
    for j, call_value in ipairs(positional_call_values) do
        aligned[#aligned + 1] = {
            name = signature[j].name,
            value = call_value["value"],
            node = call_value["node"],
            index = signature[j].index,
            positional_only = signature[j].positional_only,
            keyword_only = signature[j].keyword_only,
            default = signature[j].default,
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

    -- -- Optionally add the remaining signature arguments that were not passed
    -- for i = #aligned + 1, #signature do
    --     aligned[#aligned + 1] = {
    --         name = signature[i].name,
    --         value = signature[i].default,
    --         node = nil,
    --         index = signature[i].index,
    --         positional_only = signature[i].positional_only,
    --         keyword_only = signature[i].keyword_only,
    --         default = signature[i].default,
    --     }
    -- end

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

---Expands the keyword arguments in the current line.
M.expand_keywords = function()
    if not lsp_supports_signature_help() then
        return
    end

    local call_nodes = get_call_nodes()

    local aligned_data = {}

    for i = #call_nodes, 1, -1 do
        local call_node = call_nodes[i]
        local aligned = process_call_code(call_node)

        -- here we can iterate backwords over the aligned arguments and insert them into the buffer
        for j = #aligned, 1, -1 do
            local data = aligned[j]
            if data["positional_only"] == true then
                -- Nothing to do here
                goto continue
            end

            ---@type TSNode
            local node = data["node"]
            local row_start, col_start, row_end, col_end = node:range()
            vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { data["name"] .. "=" .. data["value"] })

            ::continue::
        end

        aligned_data[#aligned_data + 1] = aligned
    end
end

M.contract_keywords = function()
    if not lsp_supports_signature_help() then
        return
    end

    local call_nodes = get_call_nodes()

    for i = #call_nodes, 1, -1 do
        local call_node = call_nodes[i]
        local aligned = process_call_code(call_node)

        -- here we can iterate backwords over the aligned arguments and insert them into the buffer
        for j = #aligned, 1, -1 do
            local data = aligned[j]
            if data["keyword_only"] == true then
                -- Nothing to do here
                goto continue
            end

            ---@type TSNode
            local node = data["node"]
            local row_start, col_start, row_end, col_end = node:range()
            vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { data["value"] })

            ::continue::
        end
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
