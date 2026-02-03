-- Minimal init for running tests with real LSP
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add plenary and nvim-treesitter (adjust paths as needed)
local function add_plugin(name)
  local paths = {
    -- Always check the standard user nvim data path first (handles NVIM_APPNAME isolation)
    vim.fn.expand("~/.local/share/nvim/lazy/" .. name),
    vim.fn.stdpath("data") .. "/lazy/" .. name,
    vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. name,
  }
  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.runtimepath:append(path)
      -- Also add to package.path for require() to work
      package.path = package.path .. ";" .. path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua"
      return path
    end
  end
  return nil
end

add_plugin("plenary.nvim")
add_plugin("nvim-treesitter")

-- Basic settings
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Configure pyright LSP
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(args)
    vim.lsp.start({
      name = "pyright",
      cmd = { "pyright-langserver", "--stdio" },
      root_dir = vim.fn.getcwd(),
      settings = {
        python = {
          analysis = {
            autoSearchPaths = true,
            useLibraryCodeForTypes = true,
            diagnosticMode = "workspace",
          },
        },
      },
    })
  end,
})

-- Load plenary
vim.cmd([[runtime plugin/plenary.vim]])
