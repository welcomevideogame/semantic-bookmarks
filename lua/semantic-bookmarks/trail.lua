--- Session-only trail: breadcrumb navigation through bookmark jumps.
---
--- back_stack holds positions recorded before each jump (where you were).
--- fwd_stack holds positions saved when you call back() (enables forward()).
--- Calling record() always clears fwd_stack so the trail doesn't fork.
local M = {}

local back_stack = {}
local fwd_stack  = {}
local recording  = false

function M.is_recording()
  return recording
end

--- Toggle trail recording on/off. Clears any existing trail on start.
function M.toggle()
  recording = not recording
  if recording then
    back_stack = {}
    fwd_stack  = {}
    vim.notify("[semantic-bookmarks] Trail recording started", vim.log.levels.INFO)
  else
    vim.notify(
      ("[semantic-bookmarks] Trail stopped — %d waypoint(s)"):format(#back_stack),
      vim.log.levels.INFO
    )
  end
end

local function current_pos()
  local bufnr  = vim.api.nvim_get_current_buf()
  local file   = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then return nil end
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { file = file, row = cursor[1] - 1, col = cursor[2] }
end

local function do_jump(entry)
  vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  vim.api.nvim_win_set_cursor(0, { entry.row + 1, entry.col })
end

--- Record the current cursor position before a bookmark jump.
--- Clears forward history. No-op when recording is off.
function M.record()
  if not recording then return end
  local pos = current_pos()
  if not pos then return end
  back_stack[#back_stack + 1] = pos
  fwd_stack = {}
end

--- Navigate backward along the trail.
function M.back()
  if #back_stack == 0 then
    vim.notify("[semantic-bookmarks] Trail: at beginning", vim.log.levels.INFO)
    return
  end
  local pos = current_pos()
  if pos then fwd_stack[#fwd_stack + 1] = pos end
  do_jump(table.remove(back_stack))
end

--- Navigate forward along the trail (after back()).
function M.forward()
  if #fwd_stack == 0 then
    vim.notify("[semantic-bookmarks] Trail: at end", vim.log.levels.INFO)
    return
  end
  local pos = current_pos()
  if pos then back_stack[#back_stack + 1] = pos end
  do_jump(table.remove(fwd_stack))
end

return M
