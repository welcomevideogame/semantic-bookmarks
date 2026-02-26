-- Minimal Neovim init for headless test runs.
-- Usage:
--   nvim --headless -u tests/minimal_init.lua \
--        -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
--
-- Or via: make test

-- Add this plugin to the runtime path.
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add plenary. Override PLENARY_PATH if yours differs.
local plenary_path = os.getenv("PLENARY_PATH")
  or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.runtimepath:prepend(plenary_path)

-- Source plenary's plugin file so PlenaryBustedDirectory is defined.
vim.cmd("runtime plugin/plenary.vim")

-- The Lua treesitter parser is bundled in Neovim >= 0.9 — no nvim-treesitter needed.
