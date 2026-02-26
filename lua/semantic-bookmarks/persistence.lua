--- JSON-based bookmark persistence, one file per project per git branch.
--- Stored in vim.fn.stdpath("data")/semantic-bookmarks/<project-hash>-<branch>.json
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

--- Shell command runner. Overridable in tests.
M._sys = function(cmd) return vim.fn.system(cmd) end

--- Detect the project root: git root first, cwd as fallback.
function M.project_root()
  local git_root = M._sys("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  return vim.fn.getcwd()
end

--- Return the current git branch name, or "default" if not in a git repo.
function M.git_branch()
  local branch = M._sys("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("\n", "")
  if branch == "" or branch == "HEAD" then
    return "default"
  end
  return branch
end

--- Sanitize a branch name for use in a filename.
--- Replaces path separators and other shell-unsafe chars with safe equivalents.
local function sanitize_branch(branch)
  return branch:gsub("/", "--"):gsub("[^%w%.%-_]", "_")
end

--- Return the path to the JSON bookmark file for the current project + branch.
function M.db_path()
  local root   = M.project_root()
  local branch = sanitize_branch(M.git_branch())
  return get_data_dir() .. "/" .. hash_path(root) .. "-" .. branch .. ".json"
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
