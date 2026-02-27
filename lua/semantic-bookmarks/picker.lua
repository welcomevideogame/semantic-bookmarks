--- Telescope / fzf-lua / native picker for semantic bookmarks.
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
  else -- "auto"
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
end

--- Telescope backend.
local function open_telescope(bms)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Semantic Bookmarks",
    finder = finders.new_table({
      results = bms,
      entry_maker = function(bm)
        local display = format_entry(bm)
        return { value = bm, display = display, ordinal = display }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then jump_to(sel.value) end
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
    local display          = format_entry(bm)
    entries[#entries + 1]  = display
    entry_map[display]     = bm
  end
  fzf.fzf_exec(entries, {
    prompt  = "Semantic Bookmarks> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local bm = entry_map[selected[1]]
          if bm then jump_to(bm) end
        end
      end,
    },
  })
end

--- Fallback: vim.ui.select.
local function open_native(bms)
  local items   = {}
  local bm_list = {}
  for _, bm in ipairs(bms) do
    items[#items + 1]   = format_entry(bm)
    bm_list[#bm_list + 1] = bm
  end
  vim.ui.select(items, { prompt = "Semantic Bookmarks" }, function(_, idx)
    if idx then jump_to(bm_list[idx]) end
  end)
end

--- Open the bookmark picker.
--- opts.group (string|nil): filter to this group tag only.
function M.open(opts)
  opts         = opts or {}
  local store  = require("semantic-bookmarks.store")
  local bms    = store.get_all()

  if opts.group then
    local filtered = {}
    for _, bm in ipairs(bms) do
      if bm.group == opts.group then
        filtered[#filtered + 1] = bm
      end
    end
    bms = filtered
  end

  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks", vim.log.levels.INFO)
    return
  end

  -- Sort by file then row for a predictable listing order.
  table.sort(bms, function(a, b)
    if a.file ~= b.file then return (a.file or "") < (b.file or "") end
    return (a.row or 0) < (b.row or 0)
  end)

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
