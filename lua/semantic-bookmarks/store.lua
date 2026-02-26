--- In-memory bookmark store (Iteration 1).
--- Will be replaced with a SQLite backend in Iteration 2.
local M = {}

-- Primary store: { [id] = bookmark }
local bookmarks = {}

-- Buffer index: { [bufnr] = { [id] = true } }
local buf_index = {}

--- Generate a UUID v4-like identifier.
local function new_id()
  math.randomseed(os.time() + math.random(1000))
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

  return bookmark
end

--- Delete a bookmark by id. Returns true on success.
function M.delete(id)
  local bm = bookmarks[id]
  if not bm then return false end

  if buf_index[bm.bufnr] then
    buf_index[bm.bufnr][id] = nil
  end

  bookmarks[id] = nil
  return true
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
