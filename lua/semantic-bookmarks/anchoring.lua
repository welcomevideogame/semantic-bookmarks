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

--- Return a short human-readable label for a node.
--- For named nodes (functions, classes, variables with an identifier child)
--- returns the identifier text.  For anonymous control-flow and declaration
--- nodes (if, for, const …) returns the first line of the node's source text,
--- truncated to 40 characters, so the virtual-text label reads like code.
function M.get_node_label(node, bufnr)
  local name = get_node_name(node, bufnr)
  if name then return name end

  -- Use the first non-empty line of the node's own text as the label.
  local text       = vim.treesitter.get_node_text(node, bufnr)
  local first_line = text:match("^([^\n]+)") or text
  first_line       = first_line:match("^%s*(.-)%s*$") -- strip surrounding whitespace

  if #first_line > 40 then
    first_line = first_line:sub(1, 37) .. "…"
  end

  return first_line ~= "" and first_line or node:type()
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

-- ─── Resolution pipeline ────────────────────────────────────────────────────

--- Parse one segment of a structural address into a table:
---   { node_type, name }  for "type:name"
---   { node_type, idx  }  for "type[N]"
local function parse_segment(seg)
  local node_type, name = seg:match("^([^:%[]+):(.+)$")
  if node_type then return { node_type = node_type, name = name } end
  local nt, idx = seg:match("^([^%[]+)%[(%d+)%]$")
  if nt then return { node_type = nt, idx = tonumber(idx) } end
  return nil
end

--- Walk the tree top-down following a structural address.
--- Returns the target node, or nil if any segment fails to match.
function M.resolve_by_structural(bufnr, address)
  if not address or address == "" then return nil end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return nil end
  local trees = parser:parse()
  if not trees or not trees[1] then return nil end

  local current = trees[1]:root()
  for _, seg_str in ipairs(vim.split(address, " > ", { plain = true })) do
    local seg = parse_segment(seg_str)
    if not seg then return nil end

    local found = nil
    for i = 0, current:child_count() - 1 do
      local child = current:child(i)
      if child:type() == seg.node_type then
        if seg.name then
          if get_node_name(child, bufnr) == seg.name then
            found = child
            break
          end
        elseif seg.idx ~= nil and i == seg.idx then
          found = child
          break
        end
      end
    end

    if not found then return nil end
    current = found
  end

  return current
end

--- DFS over all tree nodes looking for one whose fingerprint matches.
--- Returns the first matching node, or nil.
function M.resolve_by_fingerprint(bufnr, fingerprint)
  if not fingerprint then return nil end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return nil end
  local trees = parser:parse()
  if not trees or not trees[1] then return nil end

  local function walk(node)
    if M.compute_fingerprint(node, bufnr) == fingerprint then
      return node
    end
    for i = 0, node:child_count() - 1 do
      local result = walk(node:child(i))
      if result then return result end
    end
  end

  return walk(trees[1]:root())
end

--- Scan buffer lines for the best match to `fallback_context.line`.
--- Exact match (after trimming) wins immediately; otherwise the line with
--- the longest matching prefix covering ≥ 70 % of the target is returned.
--- Returns a 0-indexed row, or nil if nothing is close enough.
function M.resolve_by_fuzzy(bufnr, fallback_context)
  if not fallback_context or not fallback_context.line then return nil end
  local target = fallback_context.line:match("^%s*(.-)%s*$")
  if target == "" then return nil end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local threshold = math.floor(#target * 0.7)
  local best_row, best_score = nil, threshold

  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == target then
      return i - 1 -- exact match, 0-indexed
    end
    local score = 0
    for j = 1, math.min(#trimmed, #target) do
      if trimmed:sub(j, j) == target:sub(j, j) then
        score = score + 1
      else
        break
      end
    end
    if score > best_score then
      best_score = score
      best_row   = i - 1
    end
  end

  return best_row
end

--- Run the full resolution pipeline for a bookmark against the current buffer
--- state. Mutates `bm` (row, col, node_end_row, confidence, structural_address)
--- in place and returns the new confidence level.
function M.reanchor(bm, bufnr)
  if bm.has_treesitter then
    -- Strategy 1: structural address → exact
    if bm.structural_address then
      local node = M.resolve_by_structural(bufnr, bm.structural_address)
      if node then
        local sr, sc, er = node:range()
        bm.row          = sr
        bm.col          = sc
        bm.node_end_row = er
        bm.confidence   = "exact"
        return "exact"
      end
    end

    -- Strategy 2: fingerprint → probable (structural address updated to new location)
    if bm.fingerprint then
      local node = M.resolve_by_fingerprint(bufnr, bm.fingerprint)
      if node then
        local sr, sc, er = node:range()
        bm.row                = sr
        bm.col                = sc
        bm.node_end_row       = er
        bm.structural_address = M.build_structural_address(node, bufnr)
        bm.confidence         = "probable"
        return "probable"
      end
    end
  end

  -- Strategy 3: fuzzy line match → weak
  local row = M.resolve_by_fuzzy(bufnr, bm.fallback_context)
  if row then
    bm.row          = row
    bm.node_end_row = row
    bm.confidence   = "weak"
    return "weak"
  end

  bm.confidence = "lost"
  return "lost"
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

  -- Build a fast lookup set from the bookmarkable node types list.
  local allowed = config.options.node_type_priority or {}
  local allowed_set = {}
  for _, t in ipairs(allowed) do
    allowed_set[t] = true
  end

  -- Walk up from the leaf and take the FIRST (innermost) ancestor whose type
  -- is in the allowed set.  "Innermost" gives the most specific semantic unit
  -- at the cursor: if the cursor is on a `for` loop inside a function the loop
  -- is selected, not the enclosing function.
  local best = nil

  local current = leaf
  while current and current ~= root do
    if allowed_set[current:type()] then
      best = current
      break
    end
    current = current:parent()
  end

  -- If no allowed type matched (e.g. the language uses node type names not yet
  -- in the user's list), fall back to the nearest ancestor that has a
  -- meaningful identifier child.  This is language-agnostic.
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
