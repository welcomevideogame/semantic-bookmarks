--- Telescope / fzf-lua / native picker for semantic bookmarks.
---
--- Keybindings (telescope & fzf-lua):
---   <CR>   / default — jump to bookmark
---   <C-d>  / ctrl-d  — delete bookmark (telescope: refreshes in place)
---   <C-g>  / ctrl-g  — set / clear group tag
---   <C-r>  / ctrl-r  — rename bookmark label
---   <C-n>  / ctrl-n  — add / edit / clear annotation note
local M = {}

local confidence_icon = {
  exact    = "●",
  probable = "◐",
  weak     = "◌",
  lost     = "✗",
}

-- Human-readable kind labels, keyed by visualization.NODE_CATEGORY values.
local KIND_LABEL = {
  func      = "function",
  method    = "method",
  class     = "class",
  struct    = "struct",
  interface = "interface",
  enum      = "enum",
  module    = "module",
  control   = "control",
  variable  = "variable",
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

--- Derive kind label and type icon for a bookmark.
--- Returns category, kind_label, icon_glyph, icon_hl.
local function bm_kind_info(bm)
  local vis      = require("semantic-bookmarks.visualization")
  local cfg      = require("semantic-bookmarks.config").options
  local category = vis.NODE_CATEGORY[bm.node_type or ""] or ""
  local kind     = KIND_LABEL[category] or ""
  local icon     = (cfg.type_icons or {})[category] or ""
  local icon_hl  = ((cfg.signs or {})[bm.confidence or "exact"] or {}).hl or "SBSignExact"
  return category, kind, icon, icon_hl
end

--- Truncate string s to at most n display characters, appending "…".
local function trunc(s, n)
  if #s <= n then return s end
  return s:sub(1, n - 1) .. "…"
end

--- Format a single-line entry for fzf-lua and the native fallback.
--- Includes confidence icon, kind, label, note preview, and file:line.
local function format_entry(bm)
  local _, kind, _, _ = bm_kind_info(bm)
  local conf_mark = confidence_icon[bm.confidence or "exact"] or "●"
  local group_tag = bm.group and ("[" .. bm.group .. "] ") or ""
  local rel_file  = vim.fn.fnamemodify(bm.file or "", ":~:.")
  local note_str  = ""
  if bm.note and bm.note ~= "" then
    local preview = bm.note:match("^([^\n]+)") or bm.note
    note_str = "  · " .. trunc(preview, 30)
  end
  return ("%s %-10s %s%s%s  %s:%d"):format(
    conf_mark, kind, group_tag, bm.label or "?", note_str,
    rel_file, (bm.row or 0) + 1
  )
end

local function jump_to(bm)
  require("semantic-bookmarks.trail").record()
  vim.cmd("edit " .. vim.fn.fnameescape(bm.file))
  vim.api.nvim_win_set_cursor(0, { bm.row + 1, bm.col or 0 })
  require("semantic-bookmarks.store").touch(bm.id)
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

--- Prompt for a group name (synchronous) and apply it to bm.
--- Returns true if the group changed, false if cancelled/unchanged.
local function prompt_group_sync(bm)
  local input = vim.fn.input("Group (empty to clear): ", bm.group or "")
  -- vim.fn.input returns "" on both empty input AND <C-c> cancel, so we
  -- treat nil-equivalent by checking if input is an empty string deliberately.
  local new_group = input ~= "" and input or nil
  if new_group == bm.group then return false end
  bm.group = new_group
  require("semantic-bookmarks.store").save()
  return true
end

--- Async group prompt (for fzf-lua and standalone use — uses vim.ui.input).
local function prompt_group_async(bm, on_done)
  vim.ui.input(
    { prompt = "Group (empty to clear): ", default = bm.group or "" },
    function(input)
      if input == nil then return end
      bm.group = input ~= "" and input or nil
      require("semantic-bookmarks.store").save()
      if on_done then on_done() end
    end
  )
end

-- ---------------------------------------------------------------------------
-- Backends
-- ---------------------------------------------------------------------------

--- Telescope backend — rich multi-column entry display.
local function open_telescope(bms)
  local pickers       = require("telescope.pickers")
  local finders       = require("telescope.finders")
  local previewers    = require("telescope.previewers")
  local conf          = require("telescope.config").values
  local actions       = require("telescope.actions")
  local action_state  = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")
  local vis           = require("semantic-bookmarks.visualization")

  -- Fixed-width columns: icon | kind | label | note+location
  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 2  },        -- type icon (or confidence mark)
      { width = 10 },        -- kind label
      { width = 36 },        -- bookmark label (truncated)
      { remaining = true },  -- note preview + file:line
    },
  })

  local function make_display(entry)
    local bm                       = entry.value
    local _, kind, icon, icon_hl   = bm_kind_info(bm)
    -- Fall back to confidence mark when no type icon is configured.
    local glyph = icon ~= "" and icon or confidence_icon[bm.confidence or "exact"] or "●"

    local label = bm.label or "?"
    if bm.group then label = "[" .. bm.group .. "] " .. label end

    local location = vim.fn.fnamemodify(bm.file or "", ":~:.") .. ":" .. ((bm.row or 0) + 1)
    local tail     = ""
    if bm.note and bm.note ~= "" then
      local preview = bm.note:match("^([^\n]+)") or bm.note
      tail = trunc(preview, 34) .. "  "
    end
    tail = tail .. location

    return displayer({
      { glyph,            icon_hl   },
      { kind,             "Comment" },
      { trunc(label, 36), "Normal"  },
      { tail,             "Comment" },
    })
  end

  local function make_ordinal(bm)
    local _, kind = bm_kind_info(bm)
    return table.concat({
      bm.label or "",
      kind,
      bm.note  or "",
      bm.group or "",
      vim.fn.fnamemodify(bm.file or "", ":~:."),
    }, " ")
  end

  local function make_finder()
    return finders.new_table({
      results = bms,
      entry_maker = function(bm)
        return {
          value   = bm,
          display = make_display,
          ordinal = make_ordinal(bm),
        }
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
    prompt_title = "Semantic Bookmarks  [<C-d> del · <C-g> group · <C-r> rename · <C-n> note]",
    finder    = make_finder(),
    sorter    = conf.generic_sorter({}),
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

      -- <C-g>: set / clear group, refresh in place.
      map({ "i", "n" }, "<C-g>", function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local changed = prompt_group_sync(sel.value)
        if changed then
          action_state.get_current_picker(prompt_bufnr):refresh(
            make_finder(), { reset_prompt = false }
          )
        end
      end)

      -- <C-r>: rename label in place, refresh.
      map({ "i", "n" }, "<C-r>", function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local bm        = sel.value
        local new_label = vim.fn.input("Rename: ", bm.label)
        if new_label == "" or new_label == bm.label then return end
        bm.label = new_label
        require("semantic-bookmarks.store").save()
        action_state.get_current_picker(prompt_bufnr):refresh(
          make_finder(), { reset_prompt = false }
        )
      end)

      -- <C-n>: add / edit / clear annotation note, refresh in place.
      map({ "i", "n" }, "<C-n>", function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        local bm    = sel.value
        local input = vim.fn.input("Note (empty to clear): ", bm.note or "")
        bm.note = input ~= "" and input or nil
        require("semantic-bookmarks.store").save()
        action_state.get_current_picker(prompt_bufnr):refresh(
          make_finder(), { reset_prompt = false }
        )
      end)

      return true
    end,
  }):find()
end

--- fzf-lua backend.
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
    prompt  = "Bookmarks [ctrl-d:del ctrl-g:group ctrl-r:rename ctrl-n:note]> ",
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
        vim.schedule(function() prompt_group_async(bm) end)
      end,
      ["ctrl-r"] = function(selected)
        if not (selected and selected[1]) then return end
        local bm = entry_map[selected[1]]
        if not bm then return end
        vim.schedule(function()
          local new_label = vim.fn.input("Rename: ", bm.label)
          if new_label ~= "" and new_label ~= bm.label then
            bm.label = new_label
            require("semantic-bookmarks.store").save()
            open_fzf(bms)
          end
        end)
      end,
      ["ctrl-n"] = function(selected)
        if not (selected and selected[1]) then return end
        local bm = entry_map[selected[1]]
        if not bm then return end
        vim.schedule(function()
          local input = vim.fn.input("Note (empty to clear): ", bm.note or "")
          bm.note = input ~= "" and input or nil
          require("semantic-bookmarks.store").save()
          open_fzf(bms)
        end)
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
