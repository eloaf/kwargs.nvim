-- NOTE:
-- 1. **JavaScript/TypeScript**: Supports default parameters and object destructuring to simulate keyword arguments, but does not natively support mixing keyword and non-keyword arguments.
-- 2. **Ruby**: Supports keyword arguments and can mix them with positional arguments.
-- 3. **Swift**: Supports mixing keyword and positional arguments.
-- 4. **Kotlin**: Supports named arguments and can mix them with positional arguments.
-- 5. **Julia**: Supports keyword arguments and can mix them with positional arguments.
-- 6. **R**: Supports mixing keyword and positional arguments.
-- 7. **C#**: Supports named arguments and can mix them with positional arguments.
-- 8. **PHP**: Supports named arguments (from PHP 8.0) and can mix them with positional arguments.

-- NOTE: In lua there are no kwargs, but the change would happen by
-- refactoring the function to take as input a table and then every reference
-- that calls it would need to be updated to pass a table with the arguments.
-- Much more complicated than just adding kwargs to the function signature.

-- Other functionalities: could be used to rename variables that go into a function call as kwargs,
-- into the name of the variable in the function definition. This could make the variable names
-- more consistent in certain places. Or move expressions defined in kwargs to a variable definition
-- above the function call. Example
--  ```python
--  foo(a=1, b=2 + 3 * 4)
--  ```
--  would become
--  ```python
--  b = 2 + 3 * 4
--  foo(a=1, b=b)
--  ```

-- 1. Keyword Argument Toggle
-- Allow toggling between positional and keyword arguments in a function call. For example:
-- Toggle foo(a=1, b=2) back to foo(1, 2).
--
-- 2. Auto-Insert Default Values
-- When calling a function, the plugin could suggest inserting default values for omitted keyword arguments:
-- python
-- Copy code
-- def foo(a, b=42, c="hello"):
--     return a + b
-- Input: foo(1)
-- Output: foo(a=1, b=42, c="hello")
--
-- 4. Dynamic Argument Rearranging
-- Provide a shortcut to reorder function arguments based on their order in the function definition:
-- python
-- Copy code
-- foo(b=2, a=1)
-- Shortcut: Rearranges to foo(a=1, b=2).
--
-- Interesting idea: Transform Kwargs to dataclass Parameters: Refactor kwargs into a dataclass and update the function signature.

-- Suppose we have a method called func:
-- def func(self, param1, param2, /, param3, *, param4, param5):
--      print(param1, param2, param3, param4, param5)
-- It must called with
-- obj.func(10, 20, 30, param4=50, param5=60)
-- OR
-- obj.func(10, 20, param3=30, param4=50, param5=60)


local utils = require('kwargs.utils')
local parsers = require('nvim-treesitter.parsers')
local queries = require('kwargs.queries')

local debug = false

local M = {}

---BFS on the tree under `node` to find the first node of type `target_type`
---@param node TSNode
---@param target_type string
---@return TSNode
local function find_first_node_of_type_bfs(node, target_type)
    local queue = { node }

    while #queue > 0 do
        local current_node = table.remove(queue, 1) -- Dequeue the first element

        if current_node:type() == target_type then
            return current_node
        end

        for child in current_node:iter_children() do
            table.insert(queue, child) -- Enqueue child nodes
        end
    end

    error("Node not found")
end

---@param mode string
---@return table<integer, TSNode>
local function get_call_nodes(mode)
    local parser = parsers.get_parser()
    local tree = parser:parse()[1]
    local query = queries.get_query()

    local start_line, end_line

    if mode == 'v' then
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

    -- TODO: Are the results guaranteed to be in order?
    -- print("Call nodes:", vim.inspect(call_nodes))

    return call_nodes
end

--- Returns a table containing the positional and keyword arguments from the call node.
--- @param call_node TSNode
--- @return table
local function get_call_values(call_node)
    if call_node:type() ~= "call" then
        error("Node is not a call node")
    end

    local argument_list_node = find_first_node_of_type_bfs(call_node, "argument_list")

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
    local argument_list_node = find_first_node_of_type_bfs(call_node, "argument_list")

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

        ::continue:: -- WARNING:
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

---Expands the keyword arguments in the current line.
---@param mode string: The mode in which the function is called
M.expand_keywords = function(mode)
    if not lsp_supports_signature_help() then
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

        -- -- Example usage
        -- local keyword = vim.fn.expand('<cword>') -- Get the word under the cursor
        -- local help_text = get_help_contents(keyword)
        -- if help_text then
        --     print(help_text)
        -- end
        -- ```

        -- This function captures the output of the `:help` command for the given keyword and returns it as a string. You can then analyze the `help_text` variable as needed.
        return
    end

    local call_nodes = get_call_nodes(mode)

    local aligned_data = {}

    for i = #call_nodes, 1, -1 do
        local call_node = call_nodes[i]
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
            vim.api.nvim_buf_set_text(
                0,
                row_start,
                col_start,
                row_end,
                col_end,
                { data["name"] .. "=" .. data["value"] }
            )

            ::continue::
        end

        aligned_data[#aligned_data + 1] = aligned
    end
end

-- Expand keywords
--  Unexpand keywords (must re-order the arguments if necessary)
-- Insert default values
--  Remove default values if literals match the default values?
-- Total cleanup
--  Expand keywords
--  Reorder arguments
--  Insert default values

local function set_keymap(modes, lhs, rhs, opts)
    for _, mode in ipairs(modes) do
        vim.api.nvim_set_keymap(mode, lhs, rhs, opts)
    end
end

M.setup = function()
    set_keymap({ 'n', 'v' }, '<leader>ek', '<cmd>lua require("kwargs").expand_keywords(vim.fn.mode())<CR>',
        { noremap = true, silent = true })
end

return M
