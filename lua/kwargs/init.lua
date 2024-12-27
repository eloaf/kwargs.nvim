local languages = require('kwargs.languages')

local debug = false

local M = {}

local function get_language_module()
    local ft = vim.bo.filetype
    if languages[ft] then
        return languages[ft]
    else
        error("Unsupported language: " .. ft)
    end
end

M.expand_keywords = function(mode)
    local lang_module = get_language_module()
    -- TODO: Figure out if we really need to pass the mode...
    lang_module.expand_keywords(mode)
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
