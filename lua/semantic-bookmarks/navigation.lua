--- Buffer-local bookmark navigation.
local M = {}

local store = require("semantic-bookmarks.store")

--- Jump to the next bookmark in the current buffer (wraps around).
function M.next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

  local bms = store.get_for_buffer(bufnr)
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in this buffer", vim.log.levels.INFO)
    return
  end

  local bm = store.find_next(bufnr, row)
  if not bm then return end

  vim.api.nvim_win_set_cursor(0, { bm.row + 1, bm.col })
  vim.notify("[semantic-bookmarks] " .. (bm.label or "bookmark"), vim.log.levels.INFO)
end

--- Jump to the previous bookmark in the current buffer (wraps around).
function M.prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

  local bms = store.get_for_buffer(bufnr)
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in this buffer", vim.log.levels.INFO)
    return
  end

  local bm = store.find_prev(bufnr, row)
  if not bm then return end

  vim.api.nvim_win_set_cursor(0, { bm.row + 1, bm.col })
  vim.notify("[semantic-bookmarks] " .. (bm.label or "bookmark"), vim.log.levels.INFO)
end

return M
