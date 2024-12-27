local parsers = require('nvim-treesitter.parsers')

local M = {}

-- WARNING: The query is not the same between languages it seems!
-- We'll need to create a query for each language we want to support...
-- Examples:
-- NOTE: lua
-- (function_call ; [565, 0] - [565, 15]
--   name: (identifier) ; [565, 0] - [565, 6]
--   arguments: (arguments ; [565, 6] - [565, 15]
--     (number) ; [565, 7] - [565, 8]
--     (number) ; [565, 10] - [565, 11]
--     (number))) ; [565, 13] - [565, 14]
-- Foobar(1, 2, 3)

-- NOTE: python
-- (call ; [51, 0] - [51, 21]
--   function: (identifier) ; [51, 0] - [51, 12]
--   arguments: (argument_list ; [51, 12] - [51, 21]
--     (integer) ; [51, 13] - [51, 14]
--     (integer) ; [51, 16] - [51, 17]
--     (integer)))) ; [51, 19] - [51, 20]
-- fn_with_args(1, 2, 3)

-- NOTE: Python has basic kwargs with a few rules.
--   1. You can't have non-keyword arguments after keyword arguments.
--   2. Arguments after a "*" are keyword-only arguments.
--   3. The symbol / can be used to separate positional-only arguments from positional-or-keyword arguments.

-- NOTE: According to ChatGPT: https://chatgpt.com/share/670be543-bf70-800a-a3e4-1e4b7611d074
-- (
--   (call
--     function: [
--       (identifier) @function
--       (attribute
--         object: (_)* @object
--         attribute: (identifier) @method
--       )
--     ]
--     arguments: (argument_list) @arguments
--   )
-- )
local query_strings = {
    -- python = [[
    --     (
    --       (call
    --         function: [
    --           (identifier)
    --           (attribute
    --             object: (_)*
    --             attribute: (identifier)
    --           )
    --             ]
    --         arguments: (argument_list)
    --       ) @call
    --     )
    -- ]],
    python = [[
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
    ]],
    lua = [[
        (function_call
          name: (identifier) @function
          arguments: (arguments) @arguments
        )
    ]]
}

---Returns the treesitter query for the current language.
---@return vim.treesitter.Query
M.get_query = function()
    local parser = parsers.get_parser()
    local lang = parser:lang()
    local query_string = query_strings[lang]
    if query_string == nil then
        error("Query string not found for language " .. lang)
    end
    local query = vim.treesitter.query.parse(lang, query_string)
    return query
end

return M
