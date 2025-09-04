# kwargs.nvim

Neovim plugin for expanding and contracting keyword arguments in Python function calls.

Written in Lua, using [Tree-Sitter](https://tree-sitter.github.io/tree-sitter/) and [Neovim LSP](https://neovim.io/).

Inspired by the ergonomics of keyword argument manipulation in IDEs and Python editors.

<!-- panvimdoc-ignore-start -->

<!--toc:start-->

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Settings](#settings)
- [Commands](#commands)
- [How plugin works](#how-plugin-works)
- [Configuration](#configuration)
  - [Languages](#languages)

<!--toc:end-->

<!-- panvimdoc-ignore-end -->

## Features

- **Expand positional arguments to keywords**: Quickly convert positional arguments in Python calls to explicit keyword arguments using LSP function signatures.
- **Contract keyword arguments to positional**: Remove explicit keywords from arguments where possible, reverting to positional style.
- **Works anywhere in the call**: No need to move the cursor to a specific argument.
- **Visual and normal mode support**: Operate on the current line or selection.
- **Smart detection**: Uses Treesitter and LSP for robust parsing and signature detection.
- **Extensible**: Language support can be extended.

## Requirements

- [Neovim 0.9+](https://github.com/neovim/neovim/releases)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (with Python parser installed)
- [Neovim LSP](https://neovim.io/) (with a Python language server, e.g. [pyright](https://github.com/microsoft/pyright))

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'yourusername/kwargs.nvim',
  keys = { '<leader>ke', '<leader>kc' },
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('kwargs').setup()
  end,
}
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  'yourusername/kwargs.nvim',
  requires = { 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('kwargs').setup()
  end,
})
```

## Settings

No configuration is required for basic usage. The plugin sets up default key mappings:

- `<leader>ke`: Expand positional arguments to keywords
- `<leader>kc`: Contract keyword arguments to positional

You can customize key mappings by overriding the `setup()` function.

## Commands

- `:lua require('kwargs').expand_keywords()`: Expand positional arguments to keywords in the current function call.
- `:lua require('kwargs').contract_keywords()`: Contract keyword arguments to positional in the current function call.

## How plugin works

- Uses Treesitter to find function call nodes at the cursor or in the selection.
- Uses LSP signature help to get argument names and types.
- Edits the buffer to insert or remove keywords as appropriate.
- Supports both normal and visual mode operations.

## Configuration

### Languages

Currently supports Python. To add support for other languages, extend `lua/kwargs/languages/`.
