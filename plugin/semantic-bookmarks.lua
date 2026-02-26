-- Auto-loaded command definitions.
-- Users still need to call require("semantic-bookmarks").setup() to activate
-- keybindings and configure options.

vim.api.nvim_create_user_command("SBMark", function(opts)
  local label = opts.args ~= "" and opts.args or nil
  require("semantic-bookmarks").mark(label)
end, { nargs = "?", desc = "Create a semantic bookmark at the cursor node" })

vim.api.nvim_create_user_command("SBDelete", function()
  require("semantic-bookmarks").delete()
end, { desc = "Delete the semantic bookmark at (or containing) the cursor" })

vim.api.nvim_create_user_command("SBNext", function()
  require("semantic-bookmarks.navigation").next()
end, { desc = "Jump to the next bookmark in the current buffer" })

vim.api.nvim_create_user_command("SBPrev", function()
  require("semantic-bookmarks.navigation").prev()
end, { desc = "Jump to the previous bookmark in the current buffer" })
