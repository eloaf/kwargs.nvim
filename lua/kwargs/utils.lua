local M = {}

local debug = false

---Prints the message if debug is true
---@param x string | table
local function maybe_print(x)
    if debug then
        if type(x) == "table" then
            x = vim.inspect(x)
        end
        print(x)
    end
end
M.maybe_print = maybe_print

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
M.find_first_node_of_type_bfs = find_first_node_of_type_bfs

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

    maybe_print("Clients" .. #clients .. "Clients with signatureHelp" .. #clients_with_signature_help)

    if #clients_with_signature_help == 0 then
        maybe_print("No LSP client attached")
        return nil
    end

    maybe_print("LSP server supports signatureHelp")

    return clients_with_signature_help[1]
end
M.lsp_supports_signature_help = lsp_supports_signature_help

return M
