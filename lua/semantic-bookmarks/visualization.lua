--- Sign column and virtual text rendering for bookmarks.
local M = {}

local config = require("semantic-bookmarks.config")

local SIGN_GROUP = "SemanticBookmarks"
local NS = vim.api.nvim_create_namespace("semantic_bookmarks")

local SIGN_NAMES = {
  exact    = "SBMarkExact",
  probable = "SBMarkProbable",
  weak     = "SBMarkWeak",
  lost     = "SBMarkLost",
}

--- (Re-)define signs from current config. Call once during setup and
--- whenever the user reconfigures signs.
function M.define_signs()
  local s = config.options.signs or {}
  for confidence, sign_name in pairs(SIGN_NAMES) do
    local cfg = s[confidence] or {}
    vim.fn.sign_define(sign_name, {
      text   = cfg.text or "●",
      texthl = cfg.hl   or "DiagnosticInfo",
    })
  end
end

function M.setup()
  M.define_signs()
end

--- Place the sign and optional virtual text for a single bookmark.
--- `bufnr` must be valid. `bookmark.row` is 0-indexed.
local function place_one(bufnr, bm)
  local lnum = bm.row + 1 -- sign_place uses 1-indexed lines
  local sign_name = SIGN_NAMES[bm.confidence] or SIGN_NAMES.exact

  vim.fn.sign_place(0, SIGN_GROUP, sign_name, bufnr, {
    lnum     = lnum,
    priority = 10,
  })

  if config.options.virtual_text and bm.label then
    vim.api.nvim_buf_set_extmark(bufnr, NS, bm.row, 0, {
      virt_text     = { { "  " .. bm.label, "Comment" } },
      virt_text_pos = "eol",
    })
  end
end

--- Clear all semantic bookmark signs and virtual text for a buffer.
function M.clear_buffer(bufnr)
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

--- Full refresh: clear everything in `bufnr` and re-render all bookmarks.
function M.refresh_buffer(bufnr, bm_list)
  M.clear_buffer(bufnr)
  for _, bm in ipairs(bm_list) do
    place_one(bufnr, bm)
  end
end

return M
