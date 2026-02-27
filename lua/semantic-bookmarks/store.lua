--- Bookmark store with JSON persistence (Iteration 2).
local M = {}

local persistence = require("semantic-bookmarks.persistence")

-- Primary store: { [id] = bookmark }
local bookmarks = {}

-- Buffer index (session-only): { [bufnr] = { [id] = true } }
local buf_index = {}

-- File index (survives across sessions): { [file] = { [id] = true } }
local file_index = {}

--- Clear all in-memory state. Call before reloading a different branch's data.
function M.reset()
  bookmarks  = {}
  buf_index  = {}
  file_index = {}
end

--- Load persisted bookmarks for the current project into the in-memory store.
--- Call once at plugin setup. Bookmarks are indexed by file; bufnr is not
--- assigned yet — call hydrate_buffer() when a buffer is opened.
function M.setup()
  local records = persistence.load()
  for _, record in ipairs(records) do
    bookmarks[record.id] = record
    local file = record.file
    if file and file ~= "" then
      if not file_index[file] then file_index[file] = {} end
      file_index[file][record.id] = true
    end
  end
end

--- Assign a live bufnr to all bookmarks belonging to `file` and add them
--- to the buffer index so the rest of the store API can find them.
function M.hydrate_buffer(file, bufnr)
  local ids = file_index[file]
  if not ids then return end
  if not buf_index[bufnr] then buf_index[bufnr] = {} end
  for id in pairs(ids) do
    local bm = bookmarks[id]
    if bm then
      bm.bufnr = bufnr
      buf_index[bufnr][id] = true
    end
  end
end

--- Generate a UUID v4-like identifier.
--- Seeds from vim.uv.hrtime() (nanosecond precision) so rapid successive
--- calls in tests don't collide the way os.time() (second precision) would.
local function new_id()
  math.randomseed(vim.uv.hrtime())
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = c == "x" and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end))
end

--- Create a bookmark from a data table and return the stored record.
--- Required fields in `data`: bufnr, file, row, col.
function M.create(data)
  local id = new_id()
  local bookmark = vim.tbl_extend("force", data, {
    id         = id,
    confidence = "exact",
    created_at = os.time(),
    last_visited_at = nil,
  })

  bookmarks[id] = bookmark

  if not buf_index[data.bufnr] then
    buf_index[data.bufnr] = {}
  end
  buf_index[data.bufnr][id] = true

  local file = data.file
  if file and file ~= "" then
    if not file_index[file] then file_index[file] = {} end
    file_index[file][id] = true
  end

  persistence.save(bookmarks)
  return bookmark
end

--- Delete a bookmark by id. Returns true on success.
function M.delete(id)
  local bm = bookmarks[id]
  if not bm then return false end

  if bm.bufnr and buf_index[bm.bufnr] then
    buf_index[bm.bufnr][id] = nil
  end

  if bm.file and file_index[bm.file] then
    file_index[bm.file][id] = nil
  end

  bookmarks[id] = nil
  persistence.save(bookmarks)
  return true
end

--- Flush the current in-memory store to disk. Call after external mutations
--- (e.g. reanchoring) that bypass create/delete.
function M.save()
  persistence.save(bookmarks)
end

--- Stamp `last_visited_at` on a bookmark and persist.
--- Call whenever the user navigates to a bookmark.
function M.touch(id)
  local bm = bookmarks[id]
  if not bm then return end
  bm.last_visited_at = os.time()
  persistence.save(bookmarks)
end

--- Retrieve a bookmark by id.
function M.get(id)
  return bookmarks[id]
end

--- Return all bookmarks as an unsorted list.
function M.get_all()
  local result = {}
  for _, bm in pairs(bookmarks) do
    table.insert(result, bm)
  end
  return result
end

--- Return all bookmarks for a buffer, sorted ascending by row.
function M.get_for_buffer(bufnr)
  local result = {}
  local index = buf_index[bufnr]
  if not index then return result end

  for id in pairs(index) do
    local bm = bookmarks[id]
    if bm then
      table.insert(result, bm)
    end
  end

  table.sort(result, function(a, b) return a.row < b.row end)
  return result
end

--- Find the bookmark whose anchor row is exactly `row`. Used for duplicate
--- prevention when creating a new bookmark.
--- Returns the match or nil.
function M.find_exact(bufnr, row)
  for _, bm in ipairs(M.get_for_buffer(bufnr)) do
    if bm.row == row then
      return bm
    end
  end
  return nil
end

--- Find the bookmark at exactly `row`, or the innermost bookmark whose
--- node range [row, node_end_row] contains `row`. Used for deletion so the
--- cursor can be anywhere inside the bookmarked node.
--- Returns the best match or nil.
function M.find_at(bufnr, row)
  local buf_bms = M.get_for_buffer(bufnr)

  -- Exact row match wins immediately.
  for _, bm in ipairs(buf_bms) do
    if bm.row == row then
      return bm
    end
  end

  -- Range containment: return the innermost (smallest) matching bookmark.
  local best, best_size = nil, math.huge
  for _, bm in ipairs(buf_bms) do
    local end_row = bm.node_end_row or bm.row
    if row >= bm.row and row <= end_row then
      local size = end_row - bm.row
      if size < best_size then
        best = bm
        best_size = size
      end
    end
  end

  return best
end

--- Return the first bookmark after `current_row` in the buffer, wrapping around.
function M.find_next(bufnr, current_row)
  local buf_bms = M.get_for_buffer(bufnr) -- sorted ascending
  for _, bm in ipairs(buf_bms) do
    if bm.row > current_row then
      return bm
    end
  end
  return buf_bms[1] -- wrap
end

--- Return the last bookmark before `current_row` in the buffer, wrapping around.
function M.find_prev(bufnr, current_row)
  local buf_bms = M.get_for_buffer(bufnr) -- sorted ascending
  local result
  for _, bm in ipairs(buf_bms) do
    if bm.row < current_row then
      result = bm
    end
  end
  if result then return result end
  return buf_bms[#buf_bms] -- wrap
end

return M
