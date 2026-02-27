--- semantic-bookmarks.nvim — public API and setup.
local M = {}

local config        = require("semantic-bookmarks.config")
local anchoring     = require("semantic-bookmarks.anchoring")
local store         = require("semantic-bookmarks.store")
local visualization = require("semantic-bookmarks.visualization")
local navigation    = require("semantic-bookmarks.navigation")
local persistence   = require("semantic-bookmarks.persistence")

--- Plugin entry point. Call this from your Neovim config:
---   require("semantic-bookmarks").setup({ ... })
function M.setup(opts)
  config.setup(opts)
  store.setup()
  visualization.setup()
  M._register_keybindings()
  M._register_autocmds()
  M._watch_git_branch()
end

--- Reload all state for the current branch and refresh every open buffer.
local function on_branch_change(new_branch)
  store.reset()
  store.setup()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local file = vim.api.nvim_buf_get_name(bufnr)
      if file ~= "" then
        store.hydrate_buffer(file, bufnr)
        visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
      end
    end
  end

  vim.notify(
    ("[semantic-bookmarks] Switched to branch '%s'"):format(new_branch),
    vim.log.levels.INFO
  )
end

--- Watch .git/HEAD for changes and trigger a branch switch when it updates.
--- Does nothing in non-git directories.
function M._watch_git_branch()
  local root     = persistence.project_root()
  local head_path = root .. "/.git/HEAD"
  if vim.fn.filereadable(head_path) == 0 then return end

  local current_branch = persistence.git_branch()

  local watcher = vim.uv.new_fs_event()
  watcher:start(head_path, {}, vim.schedule_wrap(function()
    local new_branch = persistence.git_branch()
    if new_branch ~= current_branch then
      current_branch = new_branch
      on_branch_change(new_branch)
    end
  end))
end

--- Reanchor all bookmarks in `bufnr` and persist if anything changed.
local function reanchor_buffer(bufnr)
  local bms   = store.get_for_buffer(bufnr)
  local dirty = false
  for _, bm in ipairs(bms) do
    local old_confidence = bm.confidence
    local old_row        = bm.row
    anchoring.reanchor(bm, bufnr)
    if bm.confidence ~= old_confidence or bm.row ~= old_row then
      dirty = true
    end
  end
  if dirty then store.save() end
end

function M._register_autocmds()
  local augroup = vim.api.nvim_create_augroup("SemanticBookmarks", { clear = true })

  -- Hydrate, reanchor, and visualize bookmarks whenever a buffer is entered.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if file == "" then return end
      store.hydrate_buffer(file, ev.buf)
      reanchor_buffer(ev.buf)
      visualization.refresh_buffer(ev.buf, store.get_for_buffer(ev.buf))
    end,
  })

  -- Hydrate and reanchor any buffers already open before setup() ran.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local file = vim.api.nvim_buf_get_name(bufnr)
      if file ~= "" then
        store.hydrate_buffer(file, bufnr)
        reanchor_buffer(bufnr)
        visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
      end
    end
  end
end

--- Report on the health of all bookmarks across the project.
function M.health()
  local counts    = { exact = 0, probable = 0, weak = 0, lost = 0 }
  local lost_list = {}

  for _, bm in ipairs(store.get_all()) do
    local c = bm.confidence or "exact"
    counts[c] = (counts[c] or 0) + 1
    if c == "lost" then table.insert(lost_list, bm) end
  end

  local lines = {
    "SemanticBookmarks Health",
    "========================",
    ("  exact:    %d"):format(counts.exact),
    ("  probable: %d"):format(counts.probable),
    ("  weak:     %d"):format(counts.weak),
    ("  lost:     %d"):format(counts.lost),
  }

  if #lost_list > 0 then
    table.insert(lines, "")
    table.insert(lines, "Lost bookmarks:")
    for _, bm in ipairs(lost_list) do
      table.insert(lines, ("  - %s  (%s)"):format(bm.label or "?", bm.file or "?"))
    end
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Manually re-run the resolution pipeline for all bookmarks in the current
--- buffer and notify the user with a summary of what changed.
function M.reanchor_cmd()
  local bufnr = vim.api.nvim_get_current_buf()
  local bms   = store.get_for_buffer(bufnr)

  if #bms == 0 then
    vim.notify("[semantic-bookmarks] No bookmarks in this buffer", vim.log.levels.INFO)
    return
  end

  local changed = 0
  for _, bm in ipairs(bms) do
    local old_confidence = bm.confidence
    local old_row        = bm.row
    anchoring.reanchor(bm, bufnr)
    if bm.confidence ~= old_confidence or bm.row ~= old_row then
      changed = changed + 1
    end
  end

  store.save()
  visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
  vim.notify(
    ("[semantic-bookmarks] Reanchored %d bookmark(s) — %d updated"):format(#bms, changed),
    vim.log.levels.INFO
  )
end

function M._register_keybindings()
  local kb = config.options.keybindings or {}
  local map = function(key, fn, desc)
    if key then
      vim.keymap.set("n", key, fn, { desc = desc })
    end
  end

  local trail = require("semantic-bookmarks.trail")
  map(kb.mark,          function() M.mark() end,              "Semantic bookmark: create")
  map(kb.delete,        function() M.delete() end,            "Semantic bookmark: delete")
  map(kb.next,          function() navigation.next() end,     "Semantic bookmark: next in buffer")
  map(kb.prev,          function() navigation.prev() end,     "Semantic bookmark: prev in buffer")
  map(kb.list,          function() M.list() end,              "Semantic bookmark: open picker")
  map(kb.quickfix,      function() M.to_quickfix() end,       "Semantic bookmark: send to quickfix")
  map(kb.trail_toggle,  function() trail.toggle() end,        "Semantic bookmark: toggle trail recording")
  map(kb.trail_back,    function() trail.back() end,          "Semantic bookmark: trail back")
  map(kb.trail_forward, function() trail.forward() end,       "Semantic bookmark: trail forward")
end

--- Create a bookmark at the current cursor position.
--- `label` is optional; an auto-label is generated from the node name.
function M.mark(label)
  local bufnr  = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row    = cursor[1] - 1 -- 0-indexed
  local col    = cursor[2]

  local node, status = anchoring.resolve_node(bufnr, row, col)

  local structural_address = nil
  local fingerprint        = nil
  local auto_label         = nil
  local anchor_row         = row
  local anchor_col         = col
  local node_end_row       = row

  if node and status == "ok" then
    structural_address = anchoring.build_structural_address(node, bufnr)
    fingerprint        = anchoring.compute_fingerprint(node, bufnr)
    auto_label         = anchoring.get_node_label(node, bufnr)

    local sr, sc, er = node:range()
    anchor_row   = sr
    anchor_col   = sc
    node_end_row = er
  end

  -- Prevent duplicates: only block if another bookmark is anchored at the exact same row.
  if store.find_exact(bufnr, anchor_row) then
    vim.notify("[semantic-bookmarks] Bookmark already exists here", vim.log.levels.WARN)
    return
  end

  local fallback = anchoring.get_fallback_context(bufnr, row, 3)
  local final_label = label or auto_label or ("line:" .. (row + 1))

  local bm = store.create({
    bufnr              = bufnr,
    file               = vim.api.nvim_buf_get_name(bufnr),
    row                = anchor_row,
    col                = anchor_col,
    node_end_row       = node_end_row,
    label              = final_label,
    structural_address = structural_address,
    fingerprint        = fingerprint,
    fallback_context   = fallback,
    has_treesitter     = (status == "ok"),
  })

  visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
  vim.notify("[semantic-bookmarks] Created: " .. bm.label, vim.log.levels.INFO)
  return bm
end

--- Open the bookmark picker.
--- group_name (string|nil): restrict to a specific group tag.
function M.list(group_name)
  local picker = require("semantic-bookmarks.picker")
  picker.open({ group = (group_name ~= nil and group_name ~= "") and group_name or nil })
end

--- Assign (or clear) a group tag on the bookmark at the current cursor.
--- group_name == "" or nil clears the group.
function M.set_group(group_name)
  local bufnr = vim.api.nvim_get_current_buf()
  local row   = vim.api.nvim_win_get_cursor(0)[1] - 1

  local bm = store.find_at(bufnr, row)
  if not bm then
    vim.notify("[semantic-bookmarks] No bookmark at cursor", vim.log.levels.WARN)
    return
  end

  bm.group = (group_name ~= nil and group_name ~= "") and group_name or nil
  store.save()
  vim.notify(
    bm.group and ("[semantic-bookmarks] Group set: " .. bm.group)
             or  "[semantic-bookmarks] Group cleared",
    vim.log.levels.INFO
  )
end

--- Populate the quickfix list with all (or group-filtered) bookmarks.
--- group_name (string|nil): restrict to a specific group tag.
function M.to_quickfix(group_name)
  local bms = store.get_all()

  if group_name and group_name ~= "" then
    local filtered = {}
    for _, bm in ipairs(bms) do
      if bm.group == group_name then
        filtered[#filtered + 1] = bm
      end
    end
    bms = filtered
  end

  table.sort(bms, function(a, b)
    if a.file ~= b.file then return (a.file or "") < (b.file or "") end
    return (a.row or 0) < (b.row or 0)
  end)

  local qf_items = {}
  for _, bm in ipairs(bms) do
    qf_items[#qf_items + 1] = {
      filename = bm.file,
      lnum     = (bm.row or 0) + 1,
      col      = (bm.col or 0) + 1,
      text     = bm.label or "bookmark",
    }
  end

  vim.fn.setqflist(qf_items, "r")
  vim.cmd("copen")
  vim.notify(
    ("[semantic-bookmarks] Quickfix: %d bookmark(s)"):format(#qf_items),
    vim.log.levels.INFO
  )
end

--- Delete the bookmark at (or containing) the current cursor position.
function M.delete()
  local bufnr = vim.api.nvim_get_current_buf()
  local row   = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

  local bm = store.find_at(bufnr, row)
  if not bm then
    vim.notify("[semantic-bookmarks] No bookmark at cursor", vim.log.levels.WARN)
    return
  end

  store.delete(bm.id)
  visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
  vim.notify("[semantic-bookmarks] Deleted: " .. (bm.label or "bookmark"), vim.log.levels.INFO)
end

return M
