local M = {}

---Prints the message if debug is true
---@param msg string
---@param debug boolean
M.maybe_print = function(msg, debug)
    if debug then
        print(msg)
    end
end

--- Returns true if the string contains an equal sign outside of parentheses.
---@param s string
---@return boolean
M.contains_equal_outside_of_parentheses = function(s)
    for i = 1, #s do
        local char = s:sub(i, i)
        if char == "=" then
            return true
        elseif char == "(" then
            return false
        end
    end
    return false
end

return M
