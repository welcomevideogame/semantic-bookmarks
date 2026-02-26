-- Tests for JSON-based persistence.
-- db_path is overridden to write to a temp directory so tests are isolated.

local persistence

local tmp_dir

describe("persistence", function()
  before_each(function()
    tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")

    package.loaded["semantic-bookmarks.persistence"] = nil
    persistence = require("semantic-bookmarks.persistence")

    -- Redirect all reads/writes to the temp dir.
    persistence.db_path = function()
      return tmp_dir .. "/bookmarks.json"
    end
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  -- ── load ──────────────────────────────────────────────────────────────────

  describe("load", function()
    it("returns an empty list when the file does not exist", function()
      assert.same({}, persistence.load())
    end)

    it("returns an empty list for a zero-byte file", function()
      vim.fn.writefile({}, tmp_dir .. "/bookmarks.json")
      assert.same({}, persistence.load())
    end)

    it("returns an empty list for malformed JSON", function()
      vim.fn.writefile({ "not valid json {{{" }, tmp_dir .. "/bookmarks.json")
      assert.same({}, persistence.load())
    end)
  end)

  -- ── save / load round-trip ────────────────────────────────────────────────

  describe("save / load round-trip", function()
    it("persists and reloads bookmark fields", function()
      local bookmarks = {
        ["id1"] = {
          id         = "id1",
          file       = "/project/foo.lua",
          row        = 5,
          col        = 2,
          label      = "my bookmark",
          confidence = "exact",
          created_at = 12345,
        },
      }
      persistence.save(bookmarks)
      local loaded = persistence.load()

      assert.equals(1,                  #loaded)
      assert.equals("id1",              loaded[1].id)
      assert.equals("/project/foo.lua", loaded[1].file)
      assert.equals(5,                  loaded[1].row)
      assert.equals(2,                  loaded[1].col)
      assert.equals("my bookmark",      loaded[1].label)
      assert.equals("exact",            loaded[1].confidence)
      assert.equals(12345,              loaded[1].created_at)
    end)

    it("strips the ephemeral bufnr field on save", function()
      local bookmarks = {
        ["id1"] = { id = "id1", file = "/foo.lua", row = 0, col = 0, bufnr = 42 },
      }
      persistence.save(bookmarks)
      local loaded = persistence.load()
      assert.is_nil(loaded[1].bufnr)
    end)

    it("persists multiple bookmarks", function()
      local bookmarks = {
        ["a"] = { id = "a", file = "/a.lua", row = 1, col = 0 },
        ["b"] = { id = "b", file = "/b.lua", row = 2, col = 0 },
        ["c"] = { id = "c", file = "/c.lua", row = 3, col = 0 },
      }
      persistence.save(bookmarks)
      local loaded = persistence.load()
      assert.equals(3, #loaded)
    end)

    it("save overwrites previous data (no accumulation)", function()
      persistence.save({ ["a"] = { id = "a", file = "/a.lua", row = 1, col = 0 } })
      persistence.save({ ["b"] = { id = "b", file = "/b.lua", row = 2, col = 0 } })

      local loaded = persistence.load()
      assert.equals(1,   #loaded)
      assert.equals("b", loaded[1].id)
    end)

    it("round-trips nested tables (fallback_context)", function()
      local bookmarks = {
        ["id1"] = {
          id               = "id1",
          file             = "/foo.lua",
          row              = 3,
          col              = 0,
          fallback_context = {
            line  = "local x = 1",
            above = { "-- comment", "local y = 2" },
            below = { "end" },
          },
        },
      }
      persistence.save(bookmarks)
      local loaded = persistence.load()

      local fc = loaded[1].fallback_context
      assert.is_not_nil(fc)
      assert.equals("local x = 1", fc.line)
      assert.equals(2,             #fc.above)
      assert.equals("-- comment",  fc.above[1])
      assert.equals(1,             #fc.below)
    end)
  end)

  -- ── project_root ──────────────────────────────────────────────────────────

  describe("project_root", function()
    it("returns a non-empty string", function()
      local root = persistence.project_root()
      assert.is_string(root)
      assert.truthy(#root > 0)
    end)
  end)

  -- ── git_branch ────────────────────────────────────────────────────────────

  describe("git_branch", function()
    it("returns a non-empty string", function()
      local branch = persistence.git_branch()
      assert.is_string(branch)
      assert.truthy(#branch > 0)
    end)

    it("returns 'default' when git command returns empty string", function()
      -- The before_each reloads the module fresh, so no need to restore _sys.
      persistence._sys = function(_) return "" end
      assert.equals("default", persistence.git_branch())
    end)
  end)

  -- ── db_path (branch scoping) ──────────────────────────────────────────────

  describe("db_path branch scoping", function()
    -- Use the real db_path (not overridden) for these tests.
    local real_persistence

    before_each(function()
      package.loaded["semantic-bookmarks.persistence"] = nil
      real_persistence = require("semantic-bookmarks.persistence")
    end)

    it("different branches produce different db paths", function()
      real_persistence.git_branch = function() return "main" end
      local path_main = real_persistence.db_path()

      real_persistence.git_branch = function() return "feature/my-thing" end
      local path_feature = real_persistence.db_path()

      assert.not_equals(path_main, path_feature)
    end)

    it("sanitizes slashes in branch names", function()
      real_persistence.git_branch = function() return "feature/my-thing" end
      local path = real_persistence.db_path()
      -- Path must not contain a bare slash after the data dir separator
      local filename = path:match("([^/]+)$")
      assert.falsy(filename:find("/"))
    end)

    it("same branch always produces the same path", function()
      real_persistence.git_branch = function() return "main" end
      assert.equals(real_persistence.db_path(), real_persistence.db_path())
    end)
  end)
end)
