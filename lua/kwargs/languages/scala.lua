local utils = require('kwargs.utils')
local parsers = require('nvim-treesitter.parsers')

local debug = false

local M = {}

-- Tree-sitter query for Scala function calls with arguments
local ts_query_string = [[
  (apply_expr
    fun: (_) @identifier
    arguments: (arguments
      (_)* @arg
    ) @list
  ) @call
]]

---@return table<integer, TSNode>
local function get_call_nodes()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("scala", ts_query_string)

    local start_line = nil
    local end_line = nil

    local mode = vim.api.nvim_get_mode()["mode"]

    if mode == 'V' or mode == 'v' then
        -- Visual mode
        start_line = vim.fn.line("'<") - 1
        end_line = vim.fn.line("'>")
    elseif mode == 'n' then
        -- Normal mode
        start_line = vim.fn.line('.') - 1
        end_line = start_line + 1
    else
        error("Invalid mode")
    end

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
    if call_node:type() ~= "apply_expr" then
        error("Node is not an apply expression node")
    end

    local arguments_node = utils.find_first_node_of_type_bfs(call_node, "arguments")
    if arguments_node == nil then
        error("No arguments node found")
    end

    local discarded_node_types = {
        [","] = true,
        ["("] = true,
        [")"] = true,
    }

    local result = {}

    for child_node, _ in arguments_node:iter_children() do
        if discarded_node_types[child_node:type()] == true then
            goto continue
        end

        local text = vim.treesitter.get_node_text(child_node, 0)

        local entry = { name = nil, value = text, node = child_node }
        -- In Scala, named arguments use name = value syntax
        if child_node:type() == "assign_expr" then
            local lhs_node = child_node:child(0)
            local eq_node = child_node:child(1)
            local rhs_node = child_node:child(2)
            
            if lhs_node and eq_node and rhs_node and 
               lhs_node:type() == "identifier" and 
               eq_node:type() == "=" then
                local lhs_text = vim.treesitter.get_node_text(lhs_node, 0)
                local rhs_text = vim.treesitter.get_node_text(rhs_node, 0)
                entry.name = lhs_text
                entry.value = rhs_text
            end
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
    local arguments_node = utils.find_first_node_of_type_bfs(call_node, "arguments")
    if arguments_node == nil then
        error("No arguments node found")
    end

    -- Extract the position from arguments_node
    local start_row, start_col = arguments_node:start()

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
local function get_function_signature(call_node)
    if call_node:type() ~= "apply_expr" then
        error("Node is not an apply expression node")
    end

    local params = get_params_from_call_node(call_node)

    -- Adjust position for LSP
    params.position.character = params.position.character + 1

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

    local arg_data = {}

    local keyword_only = false

    for _, arg_text in ipairs(arg_texts) do
        if arg_text == "*" then
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
            arg_name = arg_text
        elseif column_start == nil and equals_start ~= nil then
            -- No type hint but has a default value
            arg_name = string.match(arg_text, "([%a%s_]+)")
            default_value = string.match(arg_text, "[%a%s_]+ ?= ?(.+)")
        elseif column_start ~= nil and equals_start == nil then
            -- A type hint but no default value
            arg_name = string.match(arg_text, "([%a%s_]+)")
            type_hint = string.match(arg_text, "[%a%s_]+ ?: ?([^=])+")
        elseif column_start ~= nil and equals_start ~= nil then
            -- A type hint and a default value
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
            positional_only = false,
            keyword_only = signature[j].keyword_only,
            default = signature[j].default,
        }
    end

    for _, call_value in ipairs(keyword_call_values) do
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
            positional_only = false,
            keyword_only = signature[index].keyword_only,
            default = signature[index].default,
        }
    end

    return aligned
end

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

        -- here we can iterate backwards over the aligned arguments and insert them into the buffer
        for j = #aligned, 1, -1 do
            local data = aligned[j]
            if data["positional_only"] == true then
                -- Nothing to do here
                goto continue
            end

            ---@type TSNode
            local node = data["node"]
            local row_start, col_start, row_end, col_end = node:range()
            vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { data["name"] .. " = " .. data["value"] })

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

        -- here we can iterate backwards over the aligned arguments and insert them into the buffer
        for j = #aligned, 1, -1 do
            local data = aligned[j]
            if data["keyword_only"] == true then
                -- Nothing to do here
                goto continue
            end

            ---@type TSNode
            local node = data["node"]
            local row_start, col_start, row_end, col_end = node:range()
            local replacement = data["value"]
            local lines = vim.split(replacement, "\n", { trimempty = true })

            -- Clamp col_end to the line length
            local line_length = #vim.api.nvim_buf_get_lines(0, row_end, row_end + 1, false)[1]
            if col_end > line_length then
                col_end = line_length
            end

            vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, lines)

            ::continue::
        end
    end
end

return M