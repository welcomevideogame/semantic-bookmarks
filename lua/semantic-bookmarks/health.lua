--- :checkhealth semantic-bookmarks
local M = {}

function M.check()
  local h = vim.health

  -- ── Neovim version ───────────────────────────────────────────────────────
  h.start("semantic-bookmarks: Neovim")
  if vim.fn.has("nvim-0.9") == 1 then
    h.ok("Neovim ≥ 0.9")
  else
    h.error("Neovim ≥ 0.9 is required")
  end

  -- ── Treesitter ────────────────────────────────────────────────────────────
  h.start("semantic-bookmarks: Treesitter")
  if vim.treesitter then
    h.ok("vim.treesitter is available")
  else
    h.error("vim.treesitter not found — structural anchoring will be unavailable")
  end

  -- ── Picker backend ────────────────────────────────────────────────────────
  h.start("semantic-bookmarks: Picker")
  local cfg_ok, config = pcall(require, "semantic-bookmarks.config")
  local preferred = cfg_ok and config.options.picker or "auto"
  h.info(('picker = "%s"'):format(preferred))

  local has_telescope = pcall(require, "telescope")
  local has_fzf       = pcall(require, "fzf-lua")

  if has_telescope then
    h.ok("telescope.nvim found")
  else
    h.info("telescope.nvim not found")
  end

  if has_fzf then
    h.ok("fzf-lua found")
  else
    h.info("fzf-lua not found")
  end

  if not has_telescope and not has_fzf then
    h.warn("Neither telescope.nvim nor fzf-lua found — falling back to vim.ui.select")
  end

  -- ── Storage ───────────────────────────────────────────────────────────────
  h.start("semantic-bookmarks: Storage")
  local p_ok, persistence = pcall(require, "semantic-bookmarks.persistence")
  if p_ok then
    local root   = persistence.project_root()
    local branch = persistence.git_branch()
    local path   = persistence.db_path()
    h.info(("Project root:  %s"):format(root))
    h.info(("Git branch:    %s"):format(branch))
    h.info(("Data file:     %s"):format(path))
    if vim.fn.filereadable(path) == 1 then
      h.ok("Data file exists")
    else
      h.info("Data file does not exist yet (created on first bookmark)")
    end
  else
    h.warn("Could not load persistence module — run setup() first")
  end

  -- ── Bookmarks ─────────────────────────────────────────────────────────────
  h.start("semantic-bookmarks: Bookmarks")
  local s_ok, store = pcall(require, "semantic-bookmarks.store")
  if not s_ok then
    h.warn("Could not load store module — run setup() first")
    return
  end

  local bms    = store.get_all()
  local counts = { exact = 0, probable = 0, weak = 0, lost = 0 }
  local lost   = {}

  for _, bm in ipairs(bms) do
    local c = bm.confidence or "exact"
    counts[c] = (counts[c] or 0) + 1
    if c == "lost" then lost[#lost + 1] = bm end
  end

  if #bms == 0 then
    h.info("No bookmarks yet — use :SBMark to create one")
    return
  end

  h.info(("Total: %d bookmark(s)"):format(#bms))

  if counts.exact    > 0 then h.ok(  ("exact:    %d"):format(counts.exact))    end
  if counts.probable > 0 then h.warn(("probable: %d  (node moved, content matched)"):format(counts.probable)) end
  if counts.weak     > 0 then h.warn(("weak:     %d  (fuzzy line match only)"):format(counts.weak))     end
  if counts.lost     > 0 then
    h.error(("lost:     %d  (could not relocate — run :SBReanchor)"):format(counts.lost))
    for _, bm in ipairs(lost) do
      h.warn(("  • [%s]  %s:%d"):format(
        bm.label or "?",
        vim.fn.fnamemodify(bm.file or "", ":~:."),
        (bm.row or 0) + 1
      ))
    end
  end
end

return M
