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

vim.api.nvim_create_user_command("SBNext", function(opts)
  local nav = require("semantic-bookmarks.navigation")
  if opts.bang then nav.next_global() else nav.next() end
end, { bang = true, desc = "Next bookmark in buffer (! = across all files)" })

vim.api.nvim_create_user_command("SBPrev", function(opts)
  local nav = require("semantic-bookmarks.navigation")
  if opts.bang then nav.prev_global() else nav.prev() end
end, { bang = true, desc = "Prev bookmark in buffer (! = across all files)" })

vim.api.nvim_create_user_command("SBHealth", function()
  require("semantic-bookmarks").health()
end, { desc = "Report confidence levels for all bookmarks in the project" })

vim.api.nvim_create_user_command("SBReanchor", function()
  require("semantic-bookmarks").reanchor_cmd()
end, { desc = "Re-run resolution pipeline for all bookmarks in the current buffer" })

vim.api.nvim_create_user_command("SBList", function(opts)
  require("semantic-bookmarks").list(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Open semantic bookmark picker (optional: group filter)" })

vim.api.nvim_create_user_command("SBRecent", function(opts)
  require("semantic-bookmarks").list_recent(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Open picker sorted by most recently visited (optional: group filter)" })

vim.api.nvim_create_user_command("SBGroup", function(opts)
  require("semantic-bookmarks").set_group(opts.args)
end, { nargs = "?", desc = "Assign (or clear) a group tag on the bookmark at cursor" })

vim.api.nvim_create_user_command("SBRename", function(opts)
  require("semantic-bookmarks").rename(opts.args)
end, { nargs = 1, desc = "Rename the bookmark at cursor" })

vim.api.nvim_create_user_command("SBClear", function(opts)
  require("semantic-bookmarks").clear(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Delete all bookmarks (optional: group filter), with confirmation" })

vim.api.nvim_create_user_command("SBQuickfix", function(opts)
  require("semantic-bookmarks").to_quickfix(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Send bookmarks to quickfix list (optional: group filter)" })

vim.api.nvim_create_user_command("SBTrail", function()
  require("semantic-bookmarks.trail").toggle()
end, { desc = "Toggle trail recording for bookmark navigation" })

vim.api.nvim_create_user_command("SBTrailBack", function()
  require("semantic-bookmarks.trail").back()
end, { desc = "Navigate back along the bookmark trail" })

vim.api.nvim_create_user_command("SBTrailForward", function()
  require("semantic-bookmarks.trail").forward()
end, { desc = "Navigate forward along the bookmark trail" })
