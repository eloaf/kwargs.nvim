local utils = require('kwargs.utils')
local parsers = require('nvim-treesitter.parsers')

local M = {}

-- local ts_query_string = [[
--     (
--       (call
--         function: [
--           (identifier) @identifier
--           (attribute
--             object: (_)
--             attribute: (identifier)
--           )
--         ]
--         arguments: (argument_list
--           (_) @arg)*
--         ) @list
--       ) @call
-- ]]
-- local ts_query_string = [[
--     (call
--       function: (identifier)
--       arguments: (argument_list
--         (_))*
--      @call)
-- ]]


local ts_query_string = [[
    (call (_)) @call
]]


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
        start_line = vim.fn.line('.') - 1
        end_line = start_line + 1
    else
        error("Invalid mode")
    end
    return start_line, end_line
end

-- Its simpler to get the node we need then find the first set of children... I think
-- Then we can produce the list of edits we need to do
-- 1. Get all call nodes in the current selection
-- 2. For each call node, get the argument_list node and the identifier node
-- 3. Get the function signature for the identifier node (or wherever the cursor needs to be at)
-- 4. Align the arguments in the argument_list node with the function signature
-- 5. Produce a list of edits to apply to the buffer (applied in reverse order). The edits are not replacing text, simply inserting new text, with `keyword=` wherever appropriate.

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

---@return table<integer, TSNode>
local function get_call_nodes()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("python", ts_query_string)

    local start_line, end_line = get_start_and_end_line()

    --- @type table<integer, TSNode>
    local call_nodes = {}
    for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
        local capture_name = query.captures[id]

        if capture_name == 'arg' then
            print("Found argument node: " .. vim.treesitter.get_node_text(node, 0))
        end

        if capture_name == "call" then
            call_nodes[#call_nodes + 1] = node
        end
    end

    return call_nodes
end

--- TODO: Duplicate
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



-- Do a more... list processing approach
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




---@return table<{call: TSNode, args: table<integer, TSNode>}>
local function get_calls_with_args()
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("python", ts_query_string)

    local start_line, end_line = get_start_and_end_line()

    ---@type table<{call: TSNode, args: table<integer, TSNode>, identifier: TSNode}>
    local result = {}

    -- get the captured call nodes and their argument_list node
    for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
        local capture_name = query.captures[id]

        if capture_name == "call" then
            local call_node = node
            local argument_list_node = get_argument_list(call_node)
            local identifier_node = utils.find_first_node_of_type_bfs(call_node, "identifier")

            -- Collect all the argument nodes in the argument_list
            local args = {}
            for child_node, _ in argument_list_node:iter_children() do
                if child_node:type() ~= "," and child_node:type() ~= "(" and child_node:type() ~= ")" then
                    args[#args + 1] = child_node
                end
            end

            result[#result + 1] = {
                call = call_node,
                args = args,
                identifier = identifier_node,
            }
        end
    end

    -- Insert the signature info in the results
    for _, call_and_args in ipairs(result) do
        local signature = get_function_signature(call_and_args.call)
        call_and_args["signature"] = signature
        call_and_args["processed"] = process_call_code(call_and_args.call)
    end

    -- Create the list of edits to apply
    -- Edits are basically just which nodes to which we should prepend the "{name}="

    ---@type table<integer, Edit>
    local edits = {}
    for _, call_and_args in ipairs(result) do
        for _, data in ipairs(call_and_args.processed) do
            if data["positional_only"] == true then
                goto continue
            end

            -- Check if the keyword is already present
            -- TODO:
            local node_text = vim.treesitter.get_node_text(data.node, 0)
            if string.sub(node_text, 1, #data.name + 1) == data.name .. "=" then
                goto continue
            end

            local row_start, col_start, _, _ = data.node:range()
            local edit = {
                row_start = row_start,
                col_start = col_start,
                -- row_start = row_start,
                -- col_start = col_start,
                text = { data.name .. "=" }, -- Only insert the keyword and equals sign
            }
            edits[#edits + 1] = edit

            ::continue::
        end
    end

    -- finally, sort the edits in reverse order by row_start and col_start
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

    -- inpsect the results
    for _, call_and_args in ipairs(result) do
        print("Call node: " .. vim.treesitter.get_node_text(call_and_args.call, 0))
        print("Identifier node: " .. vim.treesitter.get_node_text(call_and_args.identifier, 0))
        for _, arg in ipairs(call_and_args.args) do
            print("  Argument node: " .. vim.treesitter.get_node_text(arg, 0))
        end
        print("Signature: " .. vim.inspect(call_and_args.signature))
        -- print the processed data
        for _, data in ipairs(call_and_args.processed) do
            print(string.format(
                "  Processed: name=%s, value=%s, node=%s, positional_only=%s, keyword_only=%s, default=%s",
                data.name,
                data.value,
                vim.treesitter.get_node_text(data.node, 0),
                tostring(data.positional_only),
                tostring(data.keyword_only),
                tostring(data.default or "nil")
            ))
        end
        print("Edits:")
        for _, edit in ipairs(edits) do
            print(string.format("  Edit: row_start=%d, col_start=%d, text=%s",
                edit.row_start, edit.col_start, table.concat(edit.text, "")))
        end
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


-- Maybe what we need to do is collect the nodes whose text we need to update, and

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
---@field text string[]        @replacement lines; for pure insert, sr=er & sc=ec


---Expands the keyword arguments in the current line.
M.expand_keywords = function()
    if not utils.lsp_supports_signature_help() then
        error("No LSP client supports signature help")
    end

    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("python", ts_query_string)

    -- TODO: Doesn't work with visual selection - fix it.
    local start_line, end_line = get_start_and_end_line()

    ---@type table<{call: TSNode, args: table<integer, TSNode>, identifier: TSNode}>
    local result = {}

    ---@type table<integer, Edit>
    local edits = {}

    for id, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
        local capture_name = query.captures[id]

        -- TODO: Do we even need this check since we are only matching call nodes anyways?
        if capture_name == "call" then
            local call_node = node
            local argument_list_node = get_argument_list(call_node)
            -- local identifier_node = utils.find_first_node_of_type_bfs(call_node, "identifier")

            -- Collect all the argument nodes in the argument_list
            local arguments = {}
            for child_node, _ in argument_list_node:iter_children() do
                if child_node:type() ~= "," and child_node:type() ~= "(" and child_node:type() ~= ")" then
                    arguments[#arguments + 1] = child_node
                end
            end

            -- local signature = get_function_signature(call_node)

            -- result[#result + 1] = {
            --     call_node = call_node,
            --     arguments = arguments,
            --     identifier = identifier_node,
            --     signature = signature,
            --     processed = process_call_code(call_node)
            -- }

            for _, data in ipairs(process_call_code(call_node)) do
                if data["positional_only"] == true then
                    goto continue
                end

                -- Check if the keyword is already present
                -- TODO:
                local node_text = vim.treesitter.get_node_text(data.node, 0)
                if string.sub(node_text, 1, #data.name + 1) == data.name .. "=" then
                    goto continue
                end

                local row_start, col_start, _, _ = data.node:range()
                local edit = {
                    row_start = row_start,
                    col_start = col_start,
                    -- row_start = row_start,
                    -- col_start = col_start,
                    text = { data.name .. "=" }, -- Only insert the keyword and equals sign
                }
                edits[#edits + 1] = edit

                ::continue::
            end
        end
    end

    -- Create the list of edits to apply
    -- Edits are basically just which nodes to which we should prepend the "{name}="

    -- for _, call_and_args in ipairs(result) do
    --     for _, data in ipairs(call_and_args.processed) do
    --         if data["positional_only"] == true then
    --             goto continue
    --         end
    --
    --         -- Check if the keyword is already present
    --         -- TODO:
    --         local node_text = vim.treesitter.get_node_text(data.node, 0)
    --         if string.sub(node_text, 1, #data.name + 1) == data.name .. "=" then
    --             goto continue
    --         end
    --
    --         local row_start, col_start, _, _ = data.node:range()
    --         local edit = {
    --             row_start = row_start,
    --             col_start = col_start,
    --             -- row_start = row_start,
    --             -- col_start = col_start,
    --             text = { data.name .. "=" }, -- Only insert the keyword and equals sign
    --         }
    --         edits[#edits + 1] = edit
    --
    --         ::continue::
    --     end
    -- end

    -- finally, sort the edits in reverse order by row_start and col_start
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

    -- -- inpsect the results
    -- for _, call_and_args in ipairs(result) do
    --     print("Call node: " .. vim.treesitter.get_node_text(call_and_args.call, 0))
    --     print("Identifier node: " .. vim.treesitter.get_node_text(call_and_args.identifier, 0))
    --     for _, arg in ipairs(call_and_args.args) do
    --         print("  Argument node: " .. vim.treesitter.get_node_text(arg, 0))
    --     end
    --     print("Signature: " .. vim.inspect(call_and_args.signature))
    --     -- print the processed data
    --     for _, data in ipairs(call_and_args.processed) do
    --         print(string.format(
    --             "  Processed: name=%s, value=%s, node=%s, positional_only=%s, keyword_only=%s, default=%s",
    --             data.name,
    --             data.value,
    --             vim.treesitter.get_node_text(data.node, 0),
    --             tostring(data.positional_only),
    --             tostring(data.keyword_only),
    --             tostring(data.default or "nil")
    --         ))
    --     end
    --     print("Edits:")
    --     for _, edit in ipairs(edits) do
    --         print(string.format("  Edit: row_start=%d, col_start=%d, text=%s",
    --             edit.row_start, edit.col_start, table.concat(edit.text, "")))
    --     end
    -- end

    -- error("stop here")
    -- for _, call_and_arg in ipairs(call_and_args) do
    --     print("Call node: " .. vim.treesitter.get_node_text(call_and_arg.call, 0))
    --     for _, arg in ipairs(call_and_arg.args) do
    --         print("  Argument node: " .. vim.treesitter.get_node_text(arg, 0))
    --     end
    -- end

    -- -- Collect all the children of argument_list nodes across all the call nodes and store them in a table indexed their position in the text (row, col), along with the associated call node.
    -- local argument_nodes = {}
    -- for _, call_node in ipairs(call_nodes) do
    --     local argument_list_node = utils.find_first_node_of_type_bfs(call_node, "argument_list")
    --     if argument_list_node == nil then
    --         -- TODO: function can be empty inside an argument_list so maybe we don't want to raise
    --         error("No argument list node found")
    --     end
    --     for child_node, _ in argument_list_node:iter_children() do
    --         if child_node:type() ~= "," and child_node:type() ~= "(" and child_node:type() ~= ")" then
    --             local row_start, col_start = child_node:start()
    --             argument_nodes[#argument_nodes + 1] = {
    --                 node = child_node,
    --                 row_start = row_start,
    --                 col_start = col_start,
    --                 -- row_end = row_end,
    --                 -- col_end = col_end,
    --                 call_node = call_node,
    --                 text = vim.treesitter.get_node_text(child_node, 0),
    --             }
    --         end
    --     end
    -- end
    -- -- sort the table by row_start and col_start
    -- table.sort(argument_nodes, function(a, b)
    --     if a.row_start == b.row_start then
    --         return a.col_start < b.col_start
    --     end
    --     return a.row_start < b.row_start
    -- end)
    -- print(vim.inspect(argument_nodes))

    -- error("Stop here")

    -- inspect_nodes(call_nodes)

    -- local aligned_data = {}

    -- for i = #call_nodes, 1, -1 do
    --     local call_node = call_nodes[i]
    --     local aligned = process_call_code(call_node)
    --
    --     -- here we can iterate backwords over the aligned arguments and insert them into the buffer
    --     for j = #aligned, 1, -1 do
    --         local data = aligned[j]
    --         if data["positional_only"] == true then
    --             -- Nothing to do here
    --             goto continue
    --         end
    --
    --         ---@type TSNode
    --         local node = data["node"]
    --         local row_start, col_start, row_end, col_end = node:range()
    --         vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { data["name"] .. "=" .. data["value"] })
    --
    --         ::continue::
    --     end
    --
    --     aligned_data[#aligned_data + 1] = aligned
    -- end
end

M.contract_keywords = function()
    if not utils.lsp_supports_signature_help() then
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
            local replacement = data["value"]
            local lines = vim.split(replacement, "\n", { trimempty = true })
            vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, lines)

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
