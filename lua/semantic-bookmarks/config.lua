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
  },
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
  -- Ordered list of node types to prefer when anchoring.
  -- The first matching enclosing node type wins.
  node_type_priority = {
    "function_definition",
    "function_declaration",
    "method_definition",
    "method_declaration",
    "arrow_function",
    "local_function",
    "class_definition",
    "class_declaration",
    "if_statement",
    "for_statement",
    "while_statement",
    "do_statement",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
