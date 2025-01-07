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

---BFS on the tree under `node` to find the first node of type `target_type`
---@param node TSNode
---@param target_type string
---@return TSNode
M.find_first_node_of_type_bfs = function(node, target_type)
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

return M
