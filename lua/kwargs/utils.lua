local M = {}

---Prints the message if debug is true
---@param x string | table
---@param debug boolean
M.maybe_print = function(x, debug)
    if debug then
        if type(x) == "table" then
            x = vim.inspect(x)
        end
        print(x)
    end
end

return M
