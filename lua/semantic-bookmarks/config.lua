local M = {}

M.defaults = {
  keybindings = {
    mark   = "<leader>bm",
    delete = "<leader>bd",
    next   = "<leader>bn",
    prev   = "<leader>bp",
    list          = "<leader>bl",
    quickfix      = "<leader>bq",
    trail_toggle  = "<leader>bT",
    trail_back    = "<leader>b[",
    trail_forward = "<leader>b]",
    next_global   = "<leader>bN",
    prev_global   = "<leader>bP",
    recent        = "<leader>br",
  },
  -- Picker backend: "auto" | "telescope" | "fzf-lua"
  -- "auto" tries telescope first, then fzf-lua.
  picker = "auto",
  -- Icons shown before the label in virtual text, keyed by node category.
  -- Set a category to "" to hide its icon. Requires a Nerd Font.
  type_icons = {
    func      = "󰊕",
    method    = "󰆧",
    class     = "󰠱",
    struct    = "󱡠",
    interface = "󰜰",
    enum      = "󰕘",
    module    = "󰏗",
    control   = "󰅂",
    variable  = "󰀫",
  },
  -- Sign column priority. Raise this above LSP/diagnostic signs (default 10-11)
  -- if bookmark signs are being hidden. E.g. set to 20 to always win.
  sign_priority = 10,
  -- Show 1, 2, 3 … in the sign column instead of the confidence icon.
  -- The confidence colour is still applied via the sign highlight.
  numbered_signs = false,
  -- Show a floating detail window (label, group, confidence, location) when
  -- the cursor rests on a bookmarked line in normal mode (CursorHold).
  hover = false,
  signs = {
    exact    = { text = "●", hl = "SBSignExact" },
    probable = { text = "◐", hl = "SBSignProbable" },
    weak     = { text = "◌", hl = "SBSignWeak" },
    lost     = { text = "✗", hl = "SBSignLost" },
  },
  virtual_text = true,
  -- Set of node types eligible for bookmarking.  When the cursor is placed,
  -- the innermost enclosing node whose type appears in this list is chosen.
  -- Order is no longer significant for selection — add or remove types freely.
  node_type_priority = {
    -- ── Functions ──────────────────────────────────────────────────────────
    "function_definition",        -- Python, Lua, C/C++
    "function_declaration",       -- JS/TS, C/C++
    "function_item",              -- Rust
    "func_declaration",           -- Go
    "func_literal",               -- Go (anonymous)
    "local_function",             -- Lua
    "method_definition",          -- JS/TS, Python
    "method_declaration",         -- Java, C#
    "arrow_function",             -- JS/TS
    "anonymous_function",         -- various
    "function_expression",        -- JS/TS
    "generator_function",         -- JS/TS
    "generator_function_declaration", -- JS/TS
    -- ── Classes / types ────────────────────────────────────────────────────
    "class_definition",           -- Python
    "class_declaration",          -- JS/TS, Java, C#, C++
    "impl_item",                  -- Rust
    "struct_item",                -- Rust
    "struct_type",                -- Go
    "struct_declaration",         -- C/C++
    "interface_declaration",      -- JS/TS, Go, Java
    "trait_item",                 -- Rust
    "protocol_declaration",       -- Swift/ObjC
    "type_alias_declaration",     -- JS/TS
    "type_declaration",           -- Go
    "enum_item",                  -- Rust
    "enum_declaration",           -- C++, Java
    "enum_definition",            -- various
    "module",                     -- Ruby, various
    "module_declaration",         -- various
    "namespace_declaration",      -- C++, C#
    -- ── Conditionals ───────────────────────────────────────────────────────
    "if_statement",
    "if_expression",              -- Rust
    "switch_statement",           -- JS/TS, C/C++, Java, Go
    "switch_expression",          -- Java, C#
    "match_expression",           -- Rust
    "match_statement",            -- Python 3.10+
    "conditional_expression",     -- various ternaries
    -- ── Loops ──────────────────────────────────────────────────────────────
    "for_statement",              -- C/C++, Go, Java
    "for_of_statement",           -- JS/TS
    "for_in_statement",           -- JS/TS, Python
    "for_expression",             -- Rust
    "for_generic_statement",      -- Lua generic for
    "for_numeric_statement",      -- Lua numeric for
    "while_statement",
    "while_expression",           -- Rust
    "loop_expression",            -- Rust (bare loop)
    "do_statement",               -- JS/TS, Java, C/C++
    "repeat_statement",           -- Lua
    -- ── Variable declarations / assignments ────────────────────────────────
    "lexical_declaration",        -- JS/TS  const / let
    "variable_declaration",       -- JS/TS  var / C/C++
    "short_var_declaration",      -- Go  :=
    "var_declaration",            -- Go  var
    "let_declaration",            -- Rust
    "assignment",                 -- Python
    "augmented_assignment",       -- Python  +=, etc.
    "assignment_statement",       -- Lua
    "local_declaration",          -- Lua  local x = …
    "declaration",                -- C/C++ generic
    -- ── Error handling ─────────────────────────────────────────────────────
    "try_statement",
    "catch_clause",
    "finally_clause",
    "with_statement",             -- Python  with … as …
    "defer_statement",            -- Go
    -- ── Returns / throws ───────────────────────────────────────────────────
    "return_statement",
    "return_expression",          -- Rust
    "throw_statement",            -- JS/TS, Java
    "raise_statement",            -- Python
    -- ── Imports / exports ──────────────────────────────────────────────────
    "import_statement",           -- Python
    "import_declaration",         -- JS/TS
    "import_from_statement",      -- Python  from x import y
    "export_statement",           -- JS/TS
    "use_declaration",            -- Rust
    -- ── Concurrency ────────────────────────────────────────────────────────
    "go_statement",               -- Go  go func()
    "select_statement",           -- Go
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
