--- Buffer-local and cross-buffer bookmark navigation.
local M = {}

local store = require("semantic-bookmarks.store")
local trail = require("semantic-bookmarks.trail")
local vis   = require("semantic-bookmarks.visualization")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Jump to `bm`, opening its file first if needed.
--- Handles trail recording, flash, touch, and notification.
local function do_jump(bm)
  trail.record()
  local current_file = vim.api.nvim_buf_get_name(0)
  if bm.file and bm.file ~= current_file then
    vim.cmd("edit " .. vim.fn.fnameescape(bm.file))
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { bm.row + 1, bm.col or 0 })
  vis.flash(bufnr, bm.row)
  store.touch(bm.id)
  vim.notify("[semantic-bookmarks] " .. (bm.label or "bookmark"), vim.log.levels.INFO)
end

--- Return all bookmarks sorted globally by (file, row).
local function global_sorted()
  local bms = store.get_all()
  table.sort(bms, function(a, b)
    if (a.file or "") ~= (b.file or "") then
      return (a.file or "") < (b.file or "")
    end
    return (a.row or 0) < (b.row or 0)
  end)
  return bms
end

-- ---------------------------------------------------------------------------
-- In-buffer navigation
-- ---------------------------------------------------------------------------

--- Jump to the next bookmark in the current buffer (wraps around).
function M.next(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1

  local bms = store.get_for_buffer(bufnr)
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in this buffer", vim.log.levels.INFO)
    return
  end

  local bm = store.find_next(bufnr, row)
  if not bm then return end
  do_jump(bm)
end

--- Jump to the previous bookmark in the current buffer (wraps around).
function M.prev(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1

  local bms = store.get_for_buffer(bufnr)
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in this buffer", vim.log.levels.INFO)
    return
  end

  local bm = store.find_prev(bufnr, row)
  if not bm then return end
  do_jump(bm)
end

-- ---------------------------------------------------------------------------
-- Cross-buffer (global) navigation
-- ---------------------------------------------------------------------------

--- Jump to the next bookmark across all files, ordered by (file, row).
--- Wraps around from the last bookmark back to the first.
function M.next_global()
  local bms = global_sorted()
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in project", vim.log.levels.INFO)
    return
  end

  local cur_file = vim.api.nvim_buf_get_name(0)
  local cur_row  = vim.api.nvim_win_get_cursor(0)[1] - 1

  local target
  for _, bm in ipairs(bms) do
    local f = bm.file or ""
    if f > cur_file or (f == cur_file and bm.row > cur_row) then
      target = bm
      break
    end
  end

  do_jump(target or bms[1])  -- wrap to first
end

--- Jump to the previous bookmark across all files, ordered by (file, row).
--- Wraps around from the first bookmark to the last.
function M.prev_global()
  local bms = global_sorted()
  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in project", vim.log.levels.INFO)
    return
  end

  local cur_file = vim.api.nvim_buf_get_name(0)
  local cur_row  = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Walk ascending, keep updating — last match is the closest one before cursor.
  local target
  for _, bm in ipairs(bms) do
    local f = bm.file or ""
    if f < cur_file or (f == cur_file and bm.row < cur_row) then
      target = bm
    end
  end

  do_jump(target or bms[#bms])  -- wrap to last
end

return M
