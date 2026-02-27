--- Telescope / fzf-lua / native picker for semantic bookmarks.
---
--- Keybindings (telescope & fzf-lua):
---   <CR>   / default — jump to bookmark
---   <C-d>            — delete bookmark (telescope: refreshes in place)
---   <C-g>            — set / clear group tag
local M = {}

local confidence_icon = {
  exact    = "●",
  probable = "◐",
  weak     = "◌",
  lost     = "✗",
}

local function get_backend()
  local cfg    = require("semantic-bookmarks.config").options
  local picker = cfg.picker or "auto"
  if picker == "telescope" then
    return "telescope"
  elseif picker == "fzf-lua" then
    return "fzf-lua"
  else
    if pcall(require, "telescope") then return "telescope" end
    if pcall(require, "fzf-lua")   then return "fzf-lua"   end
    return "native"
  end
end

local function format_entry(bm)
  local icon      = confidence_icon[bm.confidence or "exact"] or "●"
  local group_tag = bm.group and ("[" .. bm.group .. "] ") or ""
  local rel_file  = vim.fn.fnamemodify(bm.file or "", ":~:.")
  return ("%s %s%s  %s:%d"):format(
    icon, group_tag, bm.label or "?", rel_file, (bm.row or 0) + 1
  )
end

local function jump_to(bm)
  require("semantic-bookmarks.trail").record()
  vim.cmd("edit " .. vim.fn.fnameescape(bm.file))
  vim.api.nvim_win_set_cursor(0, { bm.row + 1, bm.col or 0 })
  require("semantic-bookmarks.store").touch(bm.id)
  -- Schedule so the buffer is fully rendered before flashing.
  vim.schedule(function()
    require("semantic-bookmarks.visualization").flash(
      vim.api.nvim_get_current_buf(), bm.row
    )
  end)
end

--- Delete bm from the store and remove it from the shared bms list.
--- Also refreshes signs for the affected buffer (if loaded).
local function delete_bm(bm, bms)
  local store = require("semantic-bookmarks.store")
  store.delete(bm.id)
  for i, b in ipairs(bms) do
    if b.id == bm.id then table.remove(bms, i); break end
  end
  -- Refresh signs; fall back to file lookup if bufnr was never hydrated.
  local bufnr = bm.bufnr
  if not bufnr then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b) == bm.file then bufnr = b; break end
    end
  end
  if bufnr then
    require("semantic-bookmarks.visualization").refresh_buffer(
      bufnr, store.get_for_buffer(bufnr)
    )
  end
end

--- Prompt for a group name and apply it to bm.
--- on_done() is called (if provided) after the input is resolved.
local function prompt_group(bm, on_done)
  vim.ui.input(
    { prompt = "Group (empty to clear): ", default = bm.group or "" },
    function(input)
      if input == nil then return end  -- user cancelled
      bm.group = input ~= "" and input or nil
      require("semantic-bookmarks.store").save()
      vim.notify(
        bm.group and ("[semantic-bookmarks] Group set: " .. bm.group)
                 or  "[semantic-bookmarks] Group cleared",
        vim.log.levels.INFO
      )
      if on_done then on_done() end
    end
  )
end

-- ---------------------------------------------------------------------------
-- Backends
-- ---------------------------------------------------------------------------

--- Telescope backend. bms is the shared list so make_finder() always reflects
--- the current state after deletions.
local function open_telescope(bms)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local previewers   = require("telescope.previewers")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local vis          = require("semantic-bookmarks.visualization")

  local function make_finder()
    return finders.new_table({
      results = bms,
      entry_maker = function(bm)
        local display = format_entry(bm)
        return { value = bm, display = display, ordinal = display }
      end,
    })
  end

  local previewer = previewers.new_buffer_previewer({
    title = "Bookmark Preview",
    define_preview = function(self, entry)
      local bm = entry.value
      conf.buffer_previewer_maker(bm.file, self.state.bufnr, {
        bufname  = self.state.bufname,
        winid    = self.state.winid,
        callback = function(pbufnr)
          vis.apply_preview_highlight(pbufnr, self.state.winid, bm.row)
        end,
      })
    end,
  })

  pickers.new({}, {
    prompt_title = "Semantic Bookmarks  [<C-d> delete · <C-g> group]",
    finder   = make_finder(),
    sorter   = conf.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr, map)
      -- <CR>: jump to bookmark.
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then jump_to(sel.value) end
      end)

      -- <C-d>: delete and refresh in place.
      map({ "i", "n" }, "<C-d>", function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        delete_bm(sel.value, bms)
        if #bms == 0 then
          actions.close(prompt_bufnr)
          vim.notify("[semantic-bookmarks] No bookmarks remaining", vim.log.levels.INFO)
          return
        end
        action_state.get_current_picker(prompt_bufnr):refresh(
          make_finder(), { reset_prompt = false }
        )
      end)

      -- <C-g>: close picker, prompt for group, done.
      map({ "i", "n" }, "<C-g>", function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local bm = sel.value
        actions.close(prompt_bufnr)
        vim.schedule(function() prompt_group(bm) end)
      end)

      return true
    end,
  }):find()
end

--- fzf-lua backend. Delete re-opens the picker with the updated list.
local function open_fzf(bms)
  local fzf       = require("fzf-lua")
  local entries   = {}
  local entry_map = {}
  for _, bm in ipairs(bms) do
    local display         = format_entry(bm)
    entries[#entries + 1] = display
    entry_map[display]    = bm
  end
  fzf.fzf_exec(entries, {
    prompt  = "Semantic Bookmarks [ctrl-d:del ctrl-g:group]> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local bm = entry_map[selected[1]]
          if bm then jump_to(bm) end
        end
      end,
      ["ctrl-d"] = function(selected)
        if not (selected and selected[1]) then return end
        local bm = entry_map[selected[1]]
        if not bm then return end
        delete_bm(bm, bms)
        vim.schedule(function()
          if #bms > 0 then open_fzf(bms)
          else vim.notify("[semantic-bookmarks] No bookmarks remaining", vim.log.levels.INFO)
          end
        end)
      end,
      ["ctrl-g"] = function(selected)
        if not (selected and selected[1]) then return end
        local bm = entry_map[selected[1]]
        if not bm then return end
        vim.schedule(function() prompt_group(bm) end)
      end,
    },
  })
end

--- Fallback: vim.ui.select. Jump only; no extra actions.
local function open_native(bms)
  local items   = {}
  local bm_list = {}
  for _, bm in ipairs(bms) do
    items[#items + 1]     = format_entry(bm)
    bm_list[#bm_list + 1] = bm
  end
  vim.ui.select(items, { prompt = "Semantic Bookmarks" }, function(_, idx)
    if idx then jump_to(bm_list[idx]) end
  end)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

--- Open the bookmark picker.
--- opts.group (string|nil): filter to this group tag only.
--- opts.sort  ("file"|"recent"): "file" = file+row order (default);
---            "recent" = most recently visited first.
function M.open(opts)
  opts        = opts or {}
  local store = require("semantic-bookmarks.store")
  local bms   = store.get_all()

  if opts.group then
    local filtered = {}
    for _, bm in ipairs(bms) do
      if bm.group == opts.group then filtered[#filtered + 1] = bm end
    end
    bms = filtered
  end

  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks", vim.log.levels.INFO)
    return
  end

  if opts.sort == "recent" then
    table.sort(bms, function(a, b)
      return (a.last_visited_at or 0) > (b.last_visited_at or 0)
    end)
  else
    table.sort(bms, function(a, b)
      if a.file ~= b.file then return (a.file or "") < (b.file or "") end
      return (a.row or 0) < (b.row or 0)
    end)
  end

  local backend = get_backend()
  if backend == "telescope" then
    open_telescope(bms)
  elseif backend == "fzf-lua" then
    open_fzf(bms)
  else
    open_native(bms)
  end
end

return M
