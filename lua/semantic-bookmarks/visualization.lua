--- Sign column, virtual text, jump flash, and hover for bookmarks.
local M = {}

local config = require("semantic-bookmarks.config")

-- Maps Treesitter node types (across languages) to icon category keys.
local NODE_CATEGORY = {
  -- functions
  function_definition   = "func",  function_declaration  = "func",
  function_item         = "func",  func_declaration      = "func",
  func_literal          = "func",  local_function        = "func",
  arrow_function        = "func",  anonymous_function    = "func",
  -- methods
  method_definition     = "method", method_declaration   = "method",
  -- classes
  class_definition      = "class",  class_declaration    = "class",
  -- structs
  struct_item           = "struct", struct_type          = "struct",
  struct_declaration    = "struct",
  -- interfaces / traits
  interface_declaration = "interface", trait_item         = "interface",
  protocol_declaration  = "interface",
  -- enums
  enum_item             = "enum",   enum_declaration     = "enum",
  enum_definition       = "enum",
  -- modules / namespaces
  module                = "module", module_declaration   = "module",
  namespace_declaration = "module",
  -- control flow
  if_statement          = "control", for_statement       = "control",
  while_statement       = "control", do_statement        = "control",
}

local SIGN_GROUP = "SemanticBookmarks"
local NS         = vim.api.nvim_create_namespace("semantic_bookmarks")
local FLASH_NS   = vim.api.nvim_create_namespace("semantic_bookmarks_flash")
local PREVIEW_NS = vim.api.nvim_create_namespace("semantic_bookmarks_preview")

local SIGN_NAMES = {
  exact    = "SBMarkExact",
  probable = "SBMarkProbable",
  weak     = "SBMarkWeak",
  lost     = "SBMarkLost",
}

-- ---------------------------------------------------------------------------
-- Highlight groups
-- ---------------------------------------------------------------------------

--- Define plugin highlight groups, linked to Neovim builtins by default.
--- `default = true` means user colorscheme overrides always win.
local function define_highlights()
  local links = {
    SBSignExact    = "DiagnosticInfo",
    SBSignProbable = "DiagnosticWarn",
    SBSignWeak     = "DiagnosticWarn",
    SBSignLost     = "DiagnosticError",
    SBVirtText     = "String",
    SBJumpFlash    = "Visual",
    SBHoverNormal  = "NormalFloat",
    SBHoverBorder  = "FloatBorder",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

-- ---------------------------------------------------------------------------
-- Signs
-- ---------------------------------------------------------------------------

--- (Re-)define the static confidence-level signs from current config.
function M.define_signs()
  local s = config.options.signs or {}
  for confidence, sign_name in pairs(SIGN_NAMES) do
    local cfg = s[confidence] or {}
    vim.fn.sign_define(sign_name, {
      text   = cfg.text or "●",
      texthl = cfg.hl   or "SBSignExact",
    })
  end
end

--- Place sign and optional virtual text for a single bookmark.
--- `index` is its 1-based sort position within the buffer (for numbered_signs).
local function place_one(bufnr, bm, index)
  local lnum      = bm.row + 1
  local sign_name

  if config.options.numbered_signs then
    -- Dynamically define a per-number sign that inherits the confidence colour.
    local conf_cfg = (config.options.signs or {})[bm.confidence or "exact"] or {}
    sign_name = ("SBMarkNum%d"):format(index)
    vim.fn.sign_define(sign_name, {
      text   = tostring(index),
      texthl = conf_cfg.hl or "SBSignExact",
    })
  else
    sign_name = SIGN_NAMES[bm.confidence] or SIGN_NAMES.exact
  end

  vim.fn.sign_place(0, SIGN_GROUP, sign_name, bufnr, {
    lnum     = lnum,
    priority = 10,
  })

  if config.options.virtual_text and bm.label then
    -- Strip legacy "node_type:" prefix (old bookmarks); new ones store just the name.
    local name = bm.label:match("^[a-z][a-z_]*:(.+)$") or bm.label

    -- Look up the type icon for this node (nil-safe; old bookmarks have no node_type).
    local type_icon = ""
    if bm.node_type then
      local category = NODE_CATEGORY[bm.node_type]
      if category then
        local icons = config.options.type_icons or {}
        type_icon = (icons[category] or "") .. " "
      end
    end

    local icon_hl = (config.options.signs[bm.confidence or "exact"] or {}).hl
                    or "SBSignExact"
    vim.api.nvim_buf_set_extmark(bufnr, NS, bm.row, 0, {
      virt_text = {
        { "  ❯ " .. type_icon, icon_hl      },
        { name,                "SBVirtText"  },
      },
      virt_text_pos = "eol",
    })
  end
end

-- ---------------------------------------------------------------------------
-- Buffer rendering
-- ---------------------------------------------------------------------------

--- Clear all semantic bookmark signs and virtual text for a buffer.
function M.clear_buffer(bufnr)
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

--- Full refresh: clear everything in `bufnr` and re-render all bookmarks.
--- bm_list must be sorted by row ascending — index = display order.
function M.refresh_buffer(bufnr, bm_list)
  M.clear_buffer(bufnr)
  for i, bm in ipairs(bm_list) do
    place_one(bufnr, bm, i)
  end
end

-- ---------------------------------------------------------------------------
-- Jump flash
-- ---------------------------------------------------------------------------

--- Briefly highlight `row` in `bufnr` with SBJumpFlash, then clear after 300 ms.
function M.flash(bufnr, row)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_add_highlight(bufnr, FLASH_NS, "SBJumpFlash", row, 0, -1)
  vim.defer_fn(function()
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, FLASH_NS, 0, -1)
  end, 300)
end

-- ---------------------------------------------------------------------------
-- Hover detail float
-- ---------------------------------------------------------------------------

local conf_icon = { exact = "✓", probable = "◐", weak = "◌", lost = "✗" }

local function hover_lines(bm)
  local icon  = conf_icon[bm.confidence or "exact"] or ""
  local lines = { " ● " .. (bm.label or "bookmark"), "" }

  if bm.group then
    lines[#lines + 1] = "  group       " .. bm.group
  end
  lines[#lines + 1] = "  confidence  " .. (bm.confidence or "exact") .. " " .. icon
  lines[#lines + 1] = "  location    "
    .. vim.fn.fnamemodify(bm.file or "", ":~:.") .. ":" .. ((bm.row or 0) + 1)
  if bm.created_at then
    lines[#lines + 1] = "  created     " .. os.date("%Y-%m-%d", bm.created_at)
  end
  return lines
end

--- Open a floating detail popup for the bookmark anchored at exactly `row`.
--- No-op if hover is disabled in config or no bookmark is at that row.
function M.show_hover(bufnr, row)
  if not config.options.hover then return end
  local bm = require("semantic-bookmarks.store").find_exact(bufnr, row)
  if not bm then return end
  vim.lsp.util.open_floating_preview(hover_lines(bm), "", {
    border       = "rounded",
    focusable    = false,
    close_events = { "CursorMoved", "BufHidden", "InsertCharPre" },
    max_width    = 60,
  })
end

-- ---------------------------------------------------------------------------
-- Telescope preview helper
-- ---------------------------------------------------------------------------

--- Highlight the bookmarked row in a telescope preview buffer and scroll to it.
--- Call this from inside a buffer_previewer_maker callback.
function M.apply_preview_highlight(pbufnr, winid, row)
  vim.api.nvim_buf_clear_namespace(pbufnr, PREVIEW_NS, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, pbufnr, PREVIEW_NS, "SBJumpFlash", row, 0, -1)
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_call, winid, function()
      vim.api.nvim_win_set_cursor(winid, { row + 1, 0 })
      vim.cmd("normal! zz")
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

function M.setup()
  define_highlights()
  M.define_signs()
end

return M
