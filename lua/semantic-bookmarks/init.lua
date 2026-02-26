--- semantic-bookmarks.nvim — public API and setup.
local M = {}

local config       = require("semantic-bookmarks.config")
local anchoring    = require("semantic-bookmarks.anchoring")
local store        = require("semantic-bookmarks.store")
local visualization = require("semantic-bookmarks.visualization")
local navigation   = require("semantic-bookmarks.navigation")

--- Plugin entry point. Call this from your Neovim config:
---   require("semantic-bookmarks").setup({ ... })
function M.setup(opts)
  config.setup(opts)
  store.setup()
  visualization.setup()
  M._register_keybindings()
  M._register_autocmds()
end

function M._register_autocmds()
  local augroup = vim.api.nvim_create_augroup("SemanticBookmarks", { clear = true })

  -- Hydrate and visualize bookmarks whenever a buffer is entered.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if file == "" then return end
      store.hydrate_buffer(file, ev.buf)
      visualization.refresh_buffer(ev.buf, store.get_for_buffer(ev.buf))
    end,
  })

  -- Hydrate any buffers that were already open before setup() ran.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local file = vim.api.nvim_buf_get_name(bufnr)
      if file ~= "" then
        store.hydrate_buffer(file, bufnr)
        visualization.refresh_buffer(bufnr, store.get_for_buffer(bufnr))
      end
    end
  end
end

function M._register_keybindings()
  local kb = config.options.keybindings or {}
  local map = function(key, fn, desc)
    if key then
      vim.keymap.set("n", key, fn, { desc = desc })
    end
  end

  map(kb.mark,   function() M.mark() end,      "Semantic bookmark: create")
  map(kb.delete, function() M.delete() end,    "Semantic bookmark: delete")
  map(kb.next,   function() navigation.next() end, "Semantic bookmark: next in buffer")
  map(kb.prev,   function() navigation.prev() end, "Semantic bookmark: prev in buffer")
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
