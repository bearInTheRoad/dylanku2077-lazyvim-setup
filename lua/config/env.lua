-- Minimal .env loader.
--
-- Parses ~/.config/nvim/.env (KEY=value lines) and exposes the values through
-- the process environment (vim.env / os.getenv). Real environment variables
-- already set in the shell take precedence over .env, so `export FOO=bar` in a
-- shell always wins over a .env entry.
--
-- This keeps secrets (API keys, warehouse IDs, repo paths) out of git while
-- still letting modules read them with os.getenv().

local M = {}

local loaded = false

local function parse_line(line)
	-- trim whitespace
	line = line:match("^%s*(.-)%s*$")
	if line == "" or line:sub(1, 1) == "#" then
		return
	end
	local key, val = line:match("^([%w_]+)%s*=%s*(.*)$")
	if not key then
		return
	end
	-- strip optional surrounding quotes
	val = val:match("^%s*['\"](.-)['\"]%s*$") or val
	-- never clobber a real env var already set by the shell
	if os.getenv(key) == nil then
		vim.env[key] = val
	end
end

function M.load()
	if loaded then
		return
	end
	loaded = true
	local path = vim.fn.stdpath("config") .. "/.env"
	local f = io.open(path, "r")
	if not f then
		return
	end
	for line in f:lines() do
		parse_line(line)
	end
	f:close()
end

--- Return the value of an environment variable, loading .env first.
--- Falls back to `fallback` when unset or empty.
---@param name string
---@param fallback? string
---@return string|nil
function M.get(name, fallback)
	M.load()
	local v = os.getenv(name)
	if v == nil or v == "" then
		return fallback
	end
	return v
end

-- eagerly load once on require so config tables see populated values
M.load()

return M
