# semantic-bookmarks.nvim

Structural bookmarks for Neovim, anchored to **Treesitter nodes** rather than line numbers. Bookmarks survive refactoring, code movement, and file edits.

## Features

- Bookmarks anchor to the **innermost** meaningful Treesitter node — functions, methods, classes, loops, conditionals, variable declarations, imports, and more
- **Multi-strategy resolution** when code changes: structural address → content fingerprint → fuzzy line match
- **Confidence scoring** — `exact / probable / weak / lost` with colour-coded signs and virtual text
- **Git branch-scoped** — each branch has its own bookmark set, switching branches swaps them automatically
- **Telescope / fzf-lua / vim.ui.select** picker with in-picker delete, rename, and group actions
- **Group tags** — organise bookmarks into named groups, filter the picker and quickfix by group
- **Trail navigation** — record a breadcrumb trail as you jump and navigate back/forward
- **MRU sorting** — `:SBRecent` opens the picker sorted by most recently visited
- **Cross-buffer navigation** — `:SBNext!` / `:SBPrev!` step through every bookmark in the project
- **Annotations** — attach a freeform note to any bookmark; visible in the hover float, picker, and quickfix list
- **Rich picker display** — kind labels (`function`, `control`, `variable`, …) and note previews in telescope, styled like LSP symbol search
- **Type icons** — function, class, struct, interface, enum icons in virtual text (requires Nerd Font)
- **Jump flash** — brief line highlight when landing on a bookmark
- **Statusline integration** — `require("semantic-bookmarks").statusline()` for lualine / heirline

## Requirements

- Neovim ≥ 0.9
- [Nerd Font](https://www.nerdfonts.com/) — recommended for type icons (falls back to plain text)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) — optional, falls back to `vim.ui.select`

## Installation

### lazy.nvim

```lua
{
  "welcomevideogame/semantic-bookmarks.nvim",
  config = function()
    require("semantic-bookmarks").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "welcomevideogame/semantic-bookmarks.nvim",
  config = function()
    require("semantic-bookmarks").setup()
  end,
}
```

## Configuration

All options with their defaults:

```lua
require("semantic-bookmarks").setup({
  keybindings = {
    mark          = "<leader>bm",
    delete        = "<leader>bd",
    next          = "<leader>bn",   -- next in current buffer
    prev          = "<leader>bp",   -- prev in current buffer
    next_global   = "<leader>bN",   -- next across all files
    prev_global   = "<leader>bP",   -- prev across all files
    list          = "<leader>bl",   -- open picker
    recent        = "<leader>br",   -- open picker sorted by recency
    quickfix      = "<leader>bq",
    trail_toggle  = "<leader>bT",
    trail_back    = "<leader>b[",
    trail_forward = "<leader>b]",
  },

  -- Picker backend: "auto" | "telescope" | "fzf-lua"
  -- "auto" tries telescope first, then fzf-lua, then vim.ui.select.
  picker = "auto",

  -- Type icons shown before the label in virtual text (requires Nerd Font).
  -- Set any category to "" to hide that icon.
  type_icons = {
    func      = "󰊕",  -- functions / arrow functions
    method    = "󰆧",  -- methods
    class     = "󰠱",  -- classes, impls, type aliases
    struct    = "󱡠",  -- structs
    interface = "󰜰",  -- interfaces, traits
    enum      = "󰕘",  -- enums
    module    = "󰏗",  -- modules, namespaces, imports/exports
    control   = "󰅂",  -- if/for/while/switch/try/return …
    variable  = "󰀫",  -- const/let/var declarations, assignments
  },

  -- Sign column priority. Raise above LSP/diagnostic signs (typically 10–11)
  -- if bookmark signs are being hidden. E.g. sign_priority = 20.
  sign_priority = 10,

  -- Show 1, 2, 3 … in the sign column instead of confidence icons.
  -- The confidence colour is still applied via the sign highlight.
  numbered_signs = false,

  -- Show a floating detail window on CursorHold when cursor is on a bookmark.
  hover = false,

  -- Sign text and highlight group per confidence level.
  signs = {
    exact    = { text = "●", hl = "SBSignExact" },
    probable = { text = "◐", hl = "SBSignProbable" },
    weak     = { text = "◌", hl = "SBSignWeak" },
    lost     = { text = "✗", hl = "SBSignLost" },
  },

  -- Show the bookmark label as virtual text at the end of the line.
  virtual_text = true,

  -- Set of Treesitter node types eligible for bookmarking.
  -- The innermost matching ancestor wins — order does not affect selection.
  -- The default covers 70+ types across TS/JS, Python, Go, Rust, Lua, C/C++:
  --   functions, methods, classes, structs, interfaces, enums,
  --   if/switch/match, for/while/loop, const/let/var declarations,
  --   try/catch, return/throw, import/export, and more.
  -- Add or remove entries freely; unknown types are silently ignored.
  node_type_priority = { ... }, -- see source for full list
})
```

## Commands

| Command | Description |
|---|---|
| `:SBMark [label]` | Create a bookmark at the cursor node |
| `:SBDelete` | Delete the bookmark at (or containing) the cursor |
| `:SBNext` | Next bookmark in the current buffer |
| `:SBNext!` | Next bookmark across all files |
| `:SBPrev` | Previous bookmark in the current buffer |
| `:SBPrev!` | Previous bookmark across all files |
| `:SBList [group]` | Open picker (optional group filter) |
| `:SBRecent [group]` | Open picker sorted by most recently visited |
| `:SBGroup [name]` | Assign or clear a group tag on the bookmark at cursor |
| `:SBRename <label>` | Rename the bookmark at cursor |
| `:SBNote [text]` | Add, edit, or clear the annotation note on the bookmark at cursor |
| `:SBClear [group]` | Delete all bookmarks (optional group filter), with confirmation |
| `:SBQuickfix [group]` | Populate the quickfix list |
| `:SBTrail` | Toggle trail recording |
| `:SBTrailBack` | Navigate back along the trail |
| `:SBTrailForward` | Navigate forward along the trail |
| `:SBHealth` | Confidence breakdown across the project |
| `:SBReanchor` | Re-run the resolution pipeline for the current buffer |
| `:checkhealth semantic-bookmarks` | Full diagnostic report |

## Picker actions

When the picker is open (telescope or fzf-lua):

| Key | Action |
|---|---|
| `<CR>` / default | Jump to bookmark |
| `<C-d>` / `ctrl-d` | Delete bookmark (telescope: refreshes in place) |
| `<C-g>` / `ctrl-g` | Set or clear group tag |
| `<C-r>` / `ctrl-r` | Rename bookmark label |
| `<C-n>` / `ctrl-n` | Add, edit, or clear annotation note |

## Highlight groups

All groups use `default = true` so your colorscheme overrides always win.

| Group | Default link | Used for |
|---|---|---|
| `SBSignExact` | `DiagnosticInfo` | Exact confidence sign |
| `SBSignProbable` | `DiagnosticWarn` | Probable confidence sign |
| `SBSignWeak` | `DiagnosticWarn` | Weak confidence sign |
| `SBSignLost` | `DiagnosticError` | Lost confidence sign |
| `SBVirtText` | `String` | Virtual text label |
| `SBJumpFlash` | `Visual` | Line flash on jump |
| `SBHoverNormal` | `NormalFloat` | Hover float body |
| `SBHoverBorder` | `FloatBorder` | Hover float border |

Override example:

```lua
vim.api.nvim_set_hl(0, "SBVirtText", { fg = "#abb2bf", italic = true })
vim.api.nvim_set_hl(0, "SBJumpFlash", { bg = "#3e4451" })
```

## Statusline integration

```lua
-- lualine
{
  sections = {
    lualine_x = {
      { require("semantic-bookmarks").statusline },
    },
  },
}

-- heirline (as a component)
{
  provider = function()
    return require("semantic-bookmarks").statusline()
  end,
}
```

Returns `""` when the current buffer has no bookmarks (hides cleanly).
Returns `"● 3"` for 3 bookmarks, `"● 2 ✗1"` when one is lost.

## How it works

### Anchoring

When you create a bookmark, the plugin walks up the Treesitter tree from the cursor and selects the **innermost** ancestor whose type appears in `node_type_priority`. Placing the cursor on a `for` loop anchors to that loop; placing it on the function name anchors to the function. Three pieces of data are stored:

1. **Structural address** — the path from root to the node, e.g. `class_definition:Auth > method_definition:login`
2. **Content fingerprint** — a hash of the node's text content
3. **Fallback context** — the exact line text plus a few surrounding lines

The bookmark label is the node's identifier when one exists (e.g. `processData`), or the first line of the node's source text for unnamed nodes like loops and conditionals (e.g. `for (const entry of entries)…`).

### Annotations

Attach a freeform note to any bookmark with `:SBNote [text]` (or `<C-n>` in the picker). Notes are persisted in the same JSON file as the bookmark and appear in:

- The hover float (`hover = true` in config)
- The telescope / fzf-lua picker entry (first line, truncated)
- The quickfix list `text` field alongside the label

### Resolution pipeline

Every time a bookmarked buffer is entered, the plugin re-resolves all bookmarks:

| Strategy | Confidence | Description |
|---|---|---|
| Structural address | `exact` | Full path still matches |
| Content fingerprint | `probable` | Node moved but content is identical |
| Fuzzy line match | `weak` | Source line found by text similarity |
| — | `lost` | All strategies failed |

### Persistence

One JSON file per project per git branch, stored in `stdpath("data")/semantic-bookmarks/`. Switching git branches automatically loads the correct bookmark set; `.git/HEAD` is watched via `vim.uv.new_fs_event`.
