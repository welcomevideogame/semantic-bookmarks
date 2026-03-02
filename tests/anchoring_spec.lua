-- Tests for the Treesitter anchoring and resolution pipeline.
-- Uses the bundled Lua parser — no nvim-treesitter installation required.

local anchoring = require("semantic-bookmarks.anchoring")
local config    = require("semantic-bookmarks.config")

-- Create a scratch buffer with `lines`, parse it as Lua, return bufnr.
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.treesitter.get_parser(bufnr, "lua"):parse()
  return bufnr
end

local function node_pos(node)
  local sr, sc, er, ec = node:range()
  return { sr, sc, er, ec }
end

-- Buffer content used across most tests.
-- Rows (0-indexed):
--   0: local function greet(name)
--   1:   return "Hello, " .. name
--   2: end
--   3: (empty)
--   4: local function farewell(name)
--   5:   return "Goodbye, " .. name
--   6: end
local TEST_LINES = {
  'local function greet(name)',
  '  return "Hello, " .. name',
  'end',
  '',
  'local function farewell(name)',
  '  return "Goodbye, " .. name',
  'end',
}

describe("anchoring", function()
  local bufnr

  before_each(function()
    bufnr = make_buf(TEST_LINES)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  -- ── resolve_node ───────────────────────────────────────────────────────────

  describe("resolve_node", function()
    it("returns ok and a named node for a Lua buffer", function()
      local node, status = anchoring.resolve_node(bufnr, 0, 15) -- inside 'greet'
      assert.equals("ok", status)
      assert.is_not_nil(node)
    end)

    it("returns no_parser for a buffer with no language", function()
      local plain = vim.api.nvim_create_buf(false, true)
      local _, status = anchoring.resolve_node(plain, 0, 0)
      assert.equals("no_parser", status)
      vim.api.nvim_buf_delete(plain, { force = true })
    end)

    -- ── innermost-first selection ───────────────────────────────────────────

    describe("innermost-first selection", function()
      -- Buffer with a for loop nested inside a function.
      -- Rows (0-indexed):
      --   0: local function outer()
      --   1:   for i = 1, 10 do
      --   2:     local x = i * 2
      --   3:   end
      --   4: end
      local NESTED_LINES = {
        "local function outer()",
        "  for i = 1, 10 do",
        "    local x = i * 2",
        "  end",
        "end",
      }

      local nested_buf

      before_each(function()
        nested_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(nested_buf, 0, -1, false, NESTED_LINES)
        vim.treesitter.get_parser(nested_buf, "lua"):parse()
        -- Enable the full default node type list so all types are allowed.
        config.setup({})
      end)

      after_each(function()
        vim.api.nvim_buf_delete(nested_buf, { force = true })
      end)

      it("selects the for loop when cursor is on the for line", function()
        -- Row 1 col 2 = inside the 'for' keyword
        local node, status = anchoring.resolve_node(nested_buf, 1, 2)
        assert.equals("ok", status)
        assert.is_not_nil(node)
        -- Should be a for-loop node, not the enclosing function.
        -- (Lua grammar variants differ: for_statement / for_numeric_statement)
        local t = node:type()
        assert.truthy(
          t == "for_statement" or t == "for_numeric_statement" or t == "for_generic_statement",
          "expected a for-loop node type, got " .. t
        )
      end)

      it("selects the local declaration when cursor is on an assignment line", function()
        -- Row 2 = 'local x = i * 2'
        local node, status = anchoring.resolve_node(nested_buf, 2, 4)
        assert.equals("ok", status)
        assert.is_not_nil(node)
        -- Should be some kind of declaration node, not the for loop or function.
        -- (Grammar variants: local_declaration / variable_declaration / assignment_statement)
        local t = node:type()
        assert.truthy(
          t == "local_declaration" or t == "variable_declaration" or t == "assignment_statement",
          "expected a declaration node type, got " .. t
        )
      end)

      it("selects the function when cursor is on the function header", function()
        -- Row 0 col 15 = inside the function name 'outer'
        local node, status = anchoring.resolve_node(nested_buf, 0, 15)
        assert.equals("ok", status)
        assert.is_not_nil(node)
        -- (Grammar variants: local_function / function_declaration)
        local t = node:type()
        assert.truthy(
          t == "local_function" or t == "function_declaration",
          "expected a function node type, got " .. t
        )
      end)
    end)
  end)

  -- ── get_node_label ─────────────────────────────────────────────────────────

  describe("get_node_label", function()
    it("returns the identifier name for a named function node", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15) -- greet function
      local label   = anchoring.get_node_label(node, bufnr)
      assert.equals("greet", label)
    end)

    it("returns first-line text for a node without a name child", function()
      local inner_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(inner_buf, 0, -1, false, {
        "local function f()",
        "  for i = 1, 5 do",
        "  end",
        "end",
      })
      vim.treesitter.get_parser(inner_buf, "lua"):parse()
      config.setup({})

      local node, status = anchoring.resolve_node(inner_buf, 1, 2)
      assert.equals("ok", status)
      local t = node:type()
      assert.truthy(
        t == "for_statement" or t == "for_numeric_statement" or t == "for_generic_statement",
        "expected a for-loop node type, got " .. t
      )

      local label = anchoring.get_node_label(node, inner_buf)
      -- Label should be the first line of the for statement, not the type name
      assert.truthy(label:find("for"), "label should contain 'for', got: " .. label)
      assert.falsy(label:find("for_numeric_statement"), "label should not be raw type name")

      vim.api.nvim_buf_delete(inner_buf, { force = true })
    end)

    it("truncates labels longer than 40 characters", function()
      local inner_buf = vim.api.nvim_create_buf(false, true)
      -- A for loop with a very long line
      local long_line = "  for i = 1, 999999999999999999999999 do"
      vim.api.nvim_buf_set_lines(inner_buf, 0, -1, false, {
        "local function f()",
        long_line,
        "  end",
        "end",
      })
      vim.treesitter.get_parser(inner_buf, "lua"):parse()
      config.setup({})

      local node, _ = anchoring.resolve_node(inner_buf, 1, 2)
      local label   = anchoring.get_node_label(node, inner_buf)
      assert.truthy(#label <= 40, "label should be ≤40 chars, got " .. #label)

      vim.api.nvim_buf_delete(inner_buf, { force = true })
    end)
  end)

  -- ── build_structural_address / resolve_by_structural ──────────────────────

  describe("build_structural_address / resolve_by_structural", function()
    it("round-trips: resolve finds the node that built the address", function()
      local node, status = anchoring.resolve_node(bufnr, 0, 15)
      assert.equals("ok", status)

      local address  = anchoring.build_structural_address(node, bufnr)
      local resolved = anchoring.resolve_by_structural(bufnr, address)

      assert.is_not_nil(resolved)
      assert.same(node_pos(node), node_pos(resolved))
    end)

    it("address string contains the function name", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local address  = anchoring.build_structural_address(node, bufnr)
      assert.truthy(address:find("greet"))
    end)

    it("distinguishes two functions with different names", function()
      local greet_node,    _ = anchoring.resolve_node(bufnr, 0, 15)
      local farewell_node, _ = anchoring.resolve_node(bufnr, 4, 15)

      local addr_greet    = anchoring.build_structural_address(greet_node,    bufnr)
      local addr_farewell = anchoring.build_structural_address(farewell_node, bufnr)

      assert.not_equals(addr_greet, addr_farewell)

      local resolved_greet    = anchoring.resolve_by_structural(bufnr, addr_greet)
      local resolved_farewell = anchoring.resolve_by_structural(bufnr, addr_farewell)

      assert.same(node_pos(greet_node),    node_pos(resolved_greet))
      assert.same(node_pos(farewell_node), node_pos(resolved_farewell))
    end)

    it("returns nil for an address that references a non-existent name", function()
      local resolved = anchoring.resolve_by_structural(bufnr, "local_function:no_such_fn")
      assert.is_nil(resolved)
    end)

    it("returns nil for an empty address", function()
      assert.is_nil(anchoring.resolve_by_structural(bufnr, ""))
      assert.is_nil(anchoring.resolve_by_structural(bufnr, nil))
    end)
  end)

  -- ── compute_fingerprint / resolve_by_fingerprint ──────────────────────────

  describe("compute_fingerprint / resolve_by_fingerprint", function()
    it("fingerprint is a non-empty hex string", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local fp = anchoring.compute_fingerprint(node, bufnr)
      assert.is_string(fp)
      assert.truthy(#fp > 0)
      assert.truthy(fp:match("^%x+$"))
    end)

    it("round-trips: finds the node by its fingerprint", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local fp   = anchoring.compute_fingerprint(node, bufnr)
      local found = anchoring.resolve_by_fingerprint(bufnr, fp)

      assert.is_not_nil(found)
      assert.same(node_pos(node), node_pos(found))
    end)

    it("two different functions have different fingerprints", function()
      local greet_node,    _ = anchoring.resolve_node(bufnr, 0, 15)
      local farewell_node, _ = anchoring.resolve_node(bufnr, 4, 15)

      local fp_greet    = anchoring.compute_fingerprint(greet_node,    bufnr)
      local fp_farewell = anchoring.compute_fingerprint(farewell_node, bufnr)

      assert.not_equals(fp_greet, fp_farewell)
    end)

    it("returns nil for a fingerprint that does not exist in the tree", function()
      assert.is_nil(anchoring.resolve_by_fingerprint(bufnr, "deadbeef"))
    end)
  end)

  -- ── resolve_by_fuzzy ──────────────────────────────────────────────────────

  describe("resolve_by_fuzzy", function()
    it("finds a line by exact content match (0-indexed row)", function()
      local row = anchoring.resolve_by_fuzzy(bufnr, { line = 'local function greet(name)' })
      assert.equals(0, row)
    end)

    it("finds the correct row when the match is not the first line", function()
      local row = anchoring.resolve_by_fuzzy(bufnr, { line = 'local function farewell(name)' })
      assert.equals(4, row)
    end)

    it("strips leading whitespace before comparing", function()
      local row = anchoring.resolve_by_fuzzy(bufnr, { line = '  return "Hello, " .. name' })
      assert.equals(1, row)
    end)

    it("returns nil when no line is close enough", function()
      local row = anchoring.resolve_by_fuzzy(bufnr, { line = 'this line does not exist anywhere' })
      assert.is_nil(row)
    end)

    it("returns nil for nil or empty fallback context", function()
      assert.is_nil(anchoring.resolve_by_fuzzy(bufnr, nil))
      assert.is_nil(anchoring.resolve_by_fuzzy(bufnr, {}))
      assert.is_nil(anchoring.resolve_by_fuzzy(bufnr, { line = '' }))
    end)
  end)

  -- ── reanchor ──────────────────────────────────────────────────────────────

  describe("reanchor", function()
    local function make_bm(node, overrides)
      local sr, sc, er = node:range()
      local bm = {
        has_treesitter     = true,
        structural_address = anchoring.build_structural_address(node, bufnr),
        fingerprint        = anchoring.compute_fingerprint(node, bufnr),
        fallback_context   = anchoring.get_fallback_context(bufnr, sr, 3),
        row                = sr,
        col                = sc,
        node_end_row       = er,
        confidence         = "exact",
      }
      return vim.tbl_extend("force", bm, overrides or {})
    end

    it("returns exact when the structural address still resolves", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local bm      = make_bm(node)
      local result  = anchoring.reanchor(bm, bufnr)
      assert.equals("exact",    result)
      assert.equals("exact",    bm.confidence)
      assert.equals(0,          bm.row)
    end)

    it("returns probable when structural fails but fingerprint matches", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local bm      = make_bm(node, { structural_address = "local_function:nonexistent" })
      local result  = anchoring.reanchor(bm, bufnr)
      assert.equals("probable", result)
      assert.equals("probable", bm.confidence)
      -- Row should now point to the greet function (fingerprint found it)
      assert.equals(0, bm.row)
    end)

    it("updates structural_address to the new location on a probable match", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local bm      = make_bm(node, { structural_address = "local_function:nonexistent" })
      anchoring.reanchor(bm, bufnr)
      -- structural_address should now be the real address (built from fingerprint match)
      assert.truthy(bm.structural_address:find("greet"))
    end)

    it("returns weak when only the fallback line matches", function()
      local node, _ = anchoring.resolve_node(bufnr, 4, 15) -- farewell
      local bm = make_bm(node, {
        structural_address = "local_function:nonexistent",
        fingerprint        = "deadbeef",
        fallback_context   = { line = 'local function farewell(name)' },
      })
      local result = anchoring.reanchor(bm, bufnr)
      assert.equals("weak",    result)
      assert.equals("weak",    bm.confidence)
      assert.equals(4,         bm.row) -- farewell is on row 4
    end)

    it("returns lost when all strategies fail", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local bm = make_bm(node, {
        structural_address = "local_function:nonexistent",
        fingerprint        = "deadbeef",
        fallback_context   = { line = 'this line does not exist anywhere' },
      })
      local result = anchoring.reanchor(bm, bufnr)
      assert.equals("lost", result)
      assert.equals("lost", bm.confidence)
    end)

    it("skips treesitter strategies when has_treesitter is false", function()
      local node, _ = anchoring.resolve_node(bufnr, 0, 15)
      local bm = make_bm(node, {
        has_treesitter = false,
        -- structural_address and fingerprint are valid but should be ignored
        fallback_context = { line = 'local function greet(name)' },
      })
      local result = anchoring.reanchor(bm, bufnr)
      -- Should land on weak, not exact, since TS strategies are skipped
      assert.equals("weak", result)
      assert.equals(0, bm.row)
    end)
  end)
end)
