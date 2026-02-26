-- Tests for the bookmark store (CRUD, indexing, hydration).
-- Persistence is mocked out via package.loaded to avoid disk I/O.

local store -- declared here; re-required fresh in each before_each

local function reset_store()
  package.loaded["semantic-bookmarks.persistence"] = {
    load = function() return {} end,
    save = function() end,
  }
  package.loaded["semantic-bookmarks.store"] = nil
  store = require("semantic-bookmarks.store")
end

describe("store", function()
  before_each(reset_store)

  -- ── create / get / delete ─────────────────────────────────────────────────

  describe("create", function()
    it("returns a bookmark with an id and defaults", function()
      local bm = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      assert.is_not_nil(bm)
      assert.is_string(bm.id)
      assert.equals("/a.lua",  bm.file)
      assert.equals(5,         bm.row)
      assert.equals("exact",   bm.confidence)
      assert.is_number(bm.created_at)
    end)

    it("stored bookmark is retrievable by id", function()
      local bm = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      assert.same(bm, store.get(bm.id))
    end)

    it("two bookmarks get distinct ids", function()
      local a = store.create({ bufnr = 1, file = "/a.lua", row = 1, col = 0 })
      local b = store.create({ bufnr = 1, file = "/a.lua", row = 2, col = 0 })
      assert.not_equals(a.id, b.id)
    end)
  end)

  describe("delete", function()
    it("removes the bookmark and returns true", function()
      local bm = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      assert.is_true(store.delete(bm.id))
      assert.is_nil(store.get(bm.id))
    end)

    it("returns false for a non-existent id", function()
      assert.is_false(store.delete("no-such-id"))
    end)

    it("deleted bookmark no longer appears in get_for_buffer", function()
      local bm = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      store.delete(bm.id)
      assert.same({}, store.get_for_buffer(1))
    end)
  end)

  -- ── get_for_buffer ────────────────────────────────────────────────────────

  describe("get_for_buffer", function()
    it("returns bookmarks sorted ascending by row", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 10, col = 0 })
      store.create({ bufnr = 1, file = "/a.lua", row = 3,  col = 0 })
      store.create({ bufnr = 1, file = "/a.lua", row = 7,  col = 0 })

      local bms = store.get_for_buffer(1)
      assert.equals(3,  #bms)
      assert.equals(3,  bms[1].row)
      assert.equals(7,  bms[2].row)
      assert.equals(10, bms[3].row)
    end)

    it("is scoped per buffer — does not bleed across buffers", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 1, col = 0 })
      store.create({ bufnr = 2, file = "/b.lua", row = 2, col = 0 })

      assert.equals(1, #store.get_for_buffer(1))
      assert.equals(1, #store.get_for_buffer(2))
    end)

    it("returns an empty list for an unknown buffer", function()
      assert.same({}, store.get_for_buffer(999))
    end)
  end)

  -- ── find_exact ────────────────────────────────────────────────────────────

  describe("find_exact", function()
    it("finds a bookmark at exactly the given row", function()
      local bm = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      local found = store.find_exact(1, 5)
      assert.is_not_nil(found)
      assert.equals(bm.id, found.id)
    end)

    it("returns nil for a row inside a node range but not the anchor row", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0, node_end_row = 10 })
      assert.is_nil(store.find_exact(1, 7))
    end)

    it("returns nil when there are no bookmarks", function()
      assert.is_nil(store.find_exact(1, 0))
    end)
  end)

  -- ── find_at ───────────────────────────────────────────────────────────────

  describe("find_at", function()
    it("finds a bookmark at the exact anchor row", function()
      local bm    = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      local found = store.find_at(1, 5)
      assert.is_not_nil(found)
      assert.equals(bm.id, found.id)
    end)

    it("finds a bookmark by range containment", function()
      local bm    = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0, node_end_row = 10 })
      local found = store.find_at(1, 7)
      assert.is_not_nil(found)
      assert.equals(bm.id, found.id)
    end)

    it("returns nil when no bookmark covers the row", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0, node_end_row = 10 })
      assert.is_nil(store.find_at(1, 20))
    end)

    it("returns the innermost bookmark for nested ranges", function()
      local outer = store.create({ bufnr = 1, file = "/a.lua", row = 0, col = 0, node_end_row = 20 })
      local inner = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0, node_end_row = 10 })
      local found = store.find_at(1, 7)
      assert.equals(inner.id, found.id)
      -- Sanity check: outer exists and covers that row too
      assert.not_equals(outer.id, found.id)
    end)
  end)

  -- ── find_next / find_prev ─────────────────────────────────────────────────

  describe("find_next / find_prev", function()
    local bm1, bm2, bm3

    before_each(function()
      bm1 = store.create({ bufnr = 1, file = "/a.lua", row = 2, col = 0 })
      bm2 = store.create({ bufnr = 1, file = "/a.lua", row = 5, col = 0 })
      bm3 = store.create({ bufnr = 1, file = "/a.lua", row = 8, col = 0 })
    end)

    it("find_next returns the next bookmark after current_row", function()
      assert.equals(bm2.id, store.find_next(1, 2).id)
      assert.equals(bm3.id, store.find_next(1, 5).id)
    end)

    it("find_next wraps around to the first bookmark", function()
      assert.equals(bm1.id, store.find_next(1, 8).id)
    end)

    it("find_prev returns the last bookmark before current_row", function()
      assert.equals(bm2.id, store.find_prev(1, 8).id)
      assert.equals(bm1.id, store.find_prev(1, 5).id)
    end)

    it("find_prev wraps around to the last bookmark", function()
      assert.equals(bm3.id, store.find_prev(1, 2).id)
    end)
  end)

  -- ── reset ─────────────────────────────────────────────────────────────────

  describe("reset", function()
    it("clears all bookmarks and indices", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 1, col = 0 })
      store.create({ bufnr = 1, file = "/a.lua", row = 2, col = 0 })
      assert.equals(2, #store.get_for_buffer(1))

      store.reset()

      assert.same({}, store.get_all())
      assert.same({}, store.get_for_buffer(1))
    end)

    it("allows setup() to reload fresh data after a reset", function()
      store.create({ bufnr = 1, file = "/a.lua", row = 1, col = 0 })
      store.reset()

      -- After reset, setup with mocked data loads cleanly
      package.loaded["semantic-bookmarks.persistence"] = {
        load = function()
          return { { id = "fresh", file = "/b.lua", row = 5, col = 0,
                     confidence = "exact", created_at = 0 } }
        end,
        save = function() end,
      }
      package.loaded["semantic-bookmarks.store"] = nil
      store = require("semantic-bookmarks.store")
      store.setup()

      assert.equals(1, #store.get_all())
      assert.equals("fresh", store.get_all()[1].id)
    end)
  end)

  -- ── hydrate_buffer ────────────────────────────────────────────────────────

  describe("hydrate_buffer", function()
    it("assigns bufnr to bookmarks that were loaded without one", function()
      -- Simulate a JSON load: inject a record via mocked persistence, then setup()
      package.loaded["semantic-bookmarks.persistence"] = {
        load = function()
          return {
            { id = "test-id", file = "/foo.lua", row = 5, col = 0,
              confidence = "exact", created_at = 0 },
          }
        end,
        save = function() end,
      }
      package.loaded["semantic-bookmarks.store"] = nil
      store = require("semantic-bookmarks.store")
      store.setup()

      -- Before hydration: no bufnr, not in any buf_index
      assert.is_nil(store.get("test-id").bufnr)
      assert.same({}, store.get_for_buffer(42))

      -- After hydration
      store.hydrate_buffer("/foo.lua", 42)
      assert.equals(42, store.get("test-id").bufnr)
      assert.equals(1,  #store.get_for_buffer(42))
    end)

    it("hydrate_buffer is idempotent", function()
      package.loaded["semantic-bookmarks.persistence"] = {
        load = function()
          return {
            { id = "test-id", file = "/foo.lua", row = 5, col = 0,
              confidence = "exact", created_at = 0 },
          }
        end,
        save = function() end,
      }
      package.loaded["semantic-bookmarks.store"] = nil
      store = require("semantic-bookmarks.store")
      store.setup()

      store.hydrate_buffer("/foo.lua", 42)
      store.hydrate_buffer("/foo.lua", 42) -- second call should be safe
      assert.equals(1, #store.get_for_buffer(42))
    end)
  end)
end)
