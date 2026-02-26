--- Treesitter-based node resolution and structural address building.
local M = {}

local config = require("semantic-bookmarks.config")

-- Node type names that carry a meaningful identifier as a direct child.
-- Used when building the human-readable structural address.
local NAME_CHILD_TYPES = {
  identifier         = true,
  name               = true,
  property_identifier = true,
  type_identifier    = true,
}

--- Walk a node's direct children looking for the first name/identifier child.
--- Returns the text of that child, or nil.
local function get_node_name(node, bufnr)
  for child in node:iter_children() do
    if NAME_CHILD_TYPES[child:type()] then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

--- Build a structural address string from a node up to (but not including)
--- the tree root, e.g. "class_definition:UserService > method_definition:validate".
function M.build_structural_address(node, bufnr)
  local parts = {}
  local current = node

  while current do
    local parent = current:parent()
    if not parent then
      -- current is the root; skip it for brevity
      break
    end

    local node_type = current:type()
    local name = get_node_name(current, bufnr)

    if name then
      table.insert(parts, 1, node_type .. ":" .. name)
    else
      -- Use the child index within the parent for disambiguation.
      local idx = 0
      for i = 0, parent:child_count() - 1 do
        if parent:child(i) == current then
          idx = i
          break
        end
      end
      table.insert(parts, 1, node_type .. "[" .. idx .. "]")
    end

    current = parent
  end

  return table.concat(parts, " > ")
end

--- Return a short human-readable label for a node, e.g. "function_definition:processData".
function M.get_node_label(node, bufnr)
  local name = get_node_name(node, bufnr)
  if name then
    return node:type() .. ":" .. name
  end
  return node:type()
end

--- Compute a simple polynomial hash of the node's text content.
--- Used as a content fingerprint for secondary resolution.
function M.compute_fingerprint(node, bufnr)
  local text = vim.treesitter.get_node_text(node, bufnr)
  local hash = 0
  for i = 1, #text do
    hash = (hash * 31 + string.byte(text, i)) % (2 ^ 32)
  end
  return string.format("%08x", hash)
end

--- Collect fallback context: the exact line at `row` plus `n` lines above/below.
--- All values are 0-indexed rows; `row` is 0-indexed.
function M.get_fallback_context(bufnr, row, n)
  n = n or 3
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total = #lines

  local above_start = math.max(0, row - n)
  local below_end   = math.min(total - 1, row + n)

  local above, below = {}, {}
  for i = above_start, row - 1 do
    table.insert(above, lines[i + 1])
  end
  for i = row + 1, below_end do
    table.insert(below, lines[i + 1])
  end

  return {
    line  = lines[row + 1] or "",
    above = above,
    below = below,
  }
end

--- Resolve the cursor position (0-indexed row/col) to the most specific
--- "meaningful" enclosing Treesitter node, as ordered by config.node_type_priority.
---
--- Returns: node (TSNode), status ("ok" | "no_parser" | "no_tree" | "no_node")
function M.resolve_node(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil, "no_parser"
  end

  local trees = parser:parse()
  if not trees or not trees[1] then
    return nil, "no_tree"
  end

  local root = trees[1]:root()
  local leaf = root:named_descendant_for_range(row, col, row, col)
  if not leaf then
    return nil, "no_node"
  end

  local priority = config.options.node_type_priority or {}

  -- Build a quick lookup for O(1) priority checks.
  local priority_set = {}
  for rank, t in ipairs(priority) do
    priority_set[t] = rank
  end

  -- Walk up from the leaf, collecting all ancestors that are priority types.
  -- We want the innermost (most specific) priority node.
  local best = nil
  local best_rank = math.huge

  local current = leaf
  while current and current ~= root do
    local rank = priority_set[current:type()]
    if rank and rank < best_rank then
      best = current
      best_rank = rank
    end
    current = current:parent()
  end

  -- If no priority type matched (e.g. the language uses different node type
  -- names than our list), do a second walk looking for the nearest ancestor
  -- that has a meaningful name child.  This is language-agnostic and handles
  -- cases like Rust's `function_item` or Go's `function_declaration` not
  -- being in the user's priority list.
  if not best then
    local cur = leaf
    while cur and cur ~= root do
      if get_node_name(cur, bufnr) then
        best = cur
        break
      end
      cur = cur:parent()
    end
  end

  -- Last resort: the leaf itself (already a named node).
  if not best then
    best = leaf
  end

  return best, "ok"
end

return M
