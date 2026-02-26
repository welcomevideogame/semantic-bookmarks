--- JSON-based bookmark persistence, one file per project.
--- Stored in vim.fn.stdpath("data")/semantic-bookmarks/<project-hash>.json
local M = {}

local function hash_path(path)
  local h = 0
  for i = 1, #path do
    h = (h * 31 + string.byte(path, i)) % (2 ^ 32)
  end
  return string.format("%08x", h)
end

local function get_data_dir()
  local dir = vim.fn.stdpath("data") .. "/semantic-bookmarks"
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Detect the project root: git root first, cwd as fallback.
function M.project_root()
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  return vim.fn.getcwd()
end

--- Return the path to this project's JSON bookmark file.
function M.db_path()
  local root = M.project_root()
  return get_data_dir() .. "/" .. hash_path(root) .. ".json"
end

--- Load bookmark records from disk. Returns a list (may be empty).
--- Returned records have no `bufnr` — that field is session-ephemeral.
function M.load()
  local path = M.db_path()
  if vim.fn.filereadable(path) == 0 then return {} end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then return {} end
  local ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" then return {} end
  return decoded
end

--- Persist all bookmark records to disk.
--- `bufnr` is stripped — it is not stable across sessions.
function M.save(bookmarks)
  local path = M.db_path()
  local records = {}
  for _, bm in pairs(bookmarks) do
    local record = {}
    for k, v in pairs(bm) do
      if k ~= "bufnr" then
        record[k] = v
      end
    end
    table.insert(records, record)
  end
  local ok, encoded = pcall(vim.fn.json_encode, records)
  if not ok then return end
  vim.fn.writefile({ encoded }, path)
end

return M
