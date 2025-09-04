
# kwargs.nvim

Expands and contracts keyword arguments in function calls. Currently supports Python. Designed to be extended for Ruby, Kotlin, Swift, Julia, and similar languages.

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

- Expand positional arguments (where possible) to keywords using LSP function signatures.
- Contract keyword arguments to positional where possible.
- Expands or contracts the arguments of all the functions under the nearest function call above the cursor.

## Requirements

- nvim-treesitter (with appropriate language parser)
- Neovim LSP (with a language server, e.g. pyright)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'eloaf/kwargs.nvim',
  keys = { '<leader>ke', '<leader>kc' },
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('kwargs').setup()
  end,
}
```


## Settings

Default key mappings:

- `<leader>ke`: Expand positional arguments to keywords
- `<leader>kc`: Contract keyword arguments to positional

Key mappings can be customized in the `setup()` function.

## Commands

- `:lua require('kwargs').expand_keywords()`: Expand positional arguments to keywords in the current function call.
- `:lua require('kwargs').contract_keywords()`: Contract keyword arguments to positional in the current function call.

## How plugin works

- Uses Treesitter to find function call nodes.
- Uses LSP signature help for argument names and types.
- Edits the buffer to insert or remove keywords.
- Supports normal and visual mode.

## Configuration

### Languages

Currently supports Python. To add other languages, extend `lua/kwargs/languages/`.
