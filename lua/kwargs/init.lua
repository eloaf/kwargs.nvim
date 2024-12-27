local languages = require('kwargs.languages')

local M = {}

local function get_language_module()
    local ft = vim.bo.filetype
    if languages[ft] then
        return languages[ft]
    else
        error("Unsupported language: " .. ft)
    end
end

M.expand_keywords = function()
    local lang_module = get_language_module()
    -- TODO: Figure out if we really need to pass the mode...
    lang_module.expand_keywords()
end

M.contract_keywords = function()
    local lang_module = get_language_module()
    lang_module.contract_keywords()
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
    set_keymap({ 'n', 'v' }, '<leader>ke', '<cmd>lua require("kwargs").expand_keywords()<CR>',
        { noremap = true, silent = true })
    set_keymap({ 'n', 'v' }, '<leader>kc', '<cmd>lua require("kwargs").contract_keywords()<CR>',
        { noremap = true, silent = true })
end

return M
