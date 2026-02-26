local M = {}

M.defaults = {
  keybindings = {
    mark   = "<leader>bm",
    delete = "<leader>bd",
    next   = "<leader>bn",
    prev   = "<leader>bp",
  },
  signs = {
    exact    = { text = "●", hl = "DiagnosticInfo" },
    probable = { text = "◐", hl = "DiagnosticWarn" },
    weak     = { text = "◌", hl = "DiagnosticWarn" },
    lost     = { text = "✗", hl = "DiagnosticError" },
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
