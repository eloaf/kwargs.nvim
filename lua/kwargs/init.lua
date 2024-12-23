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
local function match_argument_nodes(mode)
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

    local results = {}

    for _, node, _, _ in query:iter_captures(tree:root(), 0, start_line, end_line) do
        local arguments_node = find_first_node_of_type_bfs(node, "argument_list")
        results[#results + 1] = arguments_node
    end

    return results
end


---@param arguments_node TSNode
---@return table
local function get_params_from_arguments_node(arguments_node)
    -- Extract the position from arguments_node
    local start_row, start_col = arguments_node:start()

    -- Create params using the position
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = { line = start_row, character = start_col }
    }
    return params
end


--- TODO: comment, rename this function? it returns the arguments list...
--- @param arguments_node TSNode
local function get_function_info(arguments_node)
    local params = get_params_from_arguments_node(arguments_node)

    -- WARNING: Not sure I understand this...
    params.position.character = params.position.character + 1
    -- params.position.line = params.position.line + 1

    local result = vim.lsp.buf_request_sync(0, "textDocument/signatureHelp", params, 10000)

    if result == nil then
        error("No result returned!")
    end

    -- TODO: May want to reformat the results...
    local key = next(result)

    local arguments = {}

    if result and result[key] and result[key].result and result[key].result.signatures then
        local signature = result[key].result.signatures[1]
        local label = signature.label
        local parameters = signature.parameters

        for _, param in ipairs(parameters) do
            local start_idx = param.label[1] + 1
            local end_idx = param.label[2]
            local arg_name = label:sub(start_idx, end_idx)
            -- split by `:` and get the first part
            arg_name = arg_name:match("([^:]+)")
            -- print("arg name=" .. arg_name)
            arguments[#arguments + 1] = arg_name
        end
    else
        error("No signature help available!")
    end

    return arguments
end

--- Returns the first LSP client that supports signature help.
---@param debug boolean: Whether to print debug information
---@return vim.lsp.Client?
local function lsp_supports_signature_help(debug)
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

--- @param arguments_node TSNode
--- @return table<number, string>
local function get_arg_node_texts(arguments_node)
    local argument_values = {}
    for i = 0, arguments_node:named_child_count() - 1 do
        local arg = arguments_node:named_child(i)
        if arg == nil then
            error("Argument is nil")
        end
        local arg_value = vim.treesitter.get_node_text(arg, 0)
        argument_values[#argument_values + 1] = arg_value
    end
    return argument_values
end


--- Returns a table of arguments using their keyword version.
---@param argument_values table<number, string>
---@param function_info table<number, string>
---@return table<number, string>
local function get_args(argument_values, function_info)
    -- NOTE: in python you can't have non-keyword arguments after keyword arguments
    -- Therefore, we can just append the rest of the arguments as they are as soon
    -- as we encounter a keyword argument.

    local args = {}

    for i = 1, #argument_values do
        local arg_name = function_info[i]
        local arg_value = argument_values[i]

        if utils.contains_equal_outside_of_parentheses(arg_value) then
            -- This is a keyword argument, we can just append the rest of the arguments
            break
        else
            args[#args + 1] = arg_name .. "=" .. arg_value
        end
    end

    for i = #args + 1, #argument_values do
        local arg_value = argument_values[i]
        args[#args + 1] = arg_value
    end

    return args
end


---Expands the keyword arguments in the current line.
---@param mode string: The mode in which the function is called
M.expand_keywords = function(mode)
    local debug = true

    if not lsp_supports_signature_help(debug) then
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

    -- local argument_nodes: table<integer, TSNode>
    local argument_nodes = match_argument_nodes(mode)
    utils.maybe_print("Argument nodes:", debug)
    for i, n in ipairs(argument_nodes) do
        local r = vim.treesitter.get_range(n)
        local start_row, start_col, end_row, end_col = r[1], r[2], r[4], r[5]
        utils.maybe_print(vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {}), debug)

        local args_node = argument_nodes[i]
        local arg_node_texts = get_arg_node_texts(args_node)
        utils.maybe_print(vim.inspect(arg_node_texts), debug)

        local function_info = get_function_info(args_node)
    end

    for i = #argument_nodes, 1, -1 do
        -- arguments_node: TSNode
        local arguments_node = argument_nodes[i]

        local function_info = get_function_info(arguments_node)
        local arg_node_texts = get_arg_node_texts(arguments_node)



        local args = get_args(arg_node_texts, function_info)
        -- TODO: Somehow deal with new lines heres? Or the existing formatting of the code?
        local repl = "(" .. table.concat(args, ", ") .. ")"
        local row_start, col_start, row_end, col_end = arguments_node:range()

        vim.api.nvim_buf_set_text(0, row_start, col_start, row_end, col_end, { repl })
    end
end

M.setup = function()
    vim.api.nvim_set_keymap(
        'n',
        '<leader>ek',
        '<cmd>lua require("kwargs").expand_keywords("n")<CR>',
        { noremap = true, silent = true }
    )
    vim.api.nvim_set_keymap(
        'v',
        '<leader>ek',
        '<cmd>lua require("kwargs").expand_keywords("v")<CR>',
        { noremap = true, silent = true }
    )
end

return M
