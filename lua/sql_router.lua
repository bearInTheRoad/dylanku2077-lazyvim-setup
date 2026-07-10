local M = {}

local env = require("config.env")

-- Substring used to detect CDP buffers. Defaults to the basename of CDP_REPO
-- (which itself contains the marker); empty when nothing is configured, in
-- which case cdp routing is disabled and everything falls back to databricks.
local CDP_MARKER = env.get("CDP_MARKER", "")
if CDP_MARKER == "" then
  local repo = env.get("CDP_REPO", "")
  CDP_MARKER = repo ~= "" and vim.fs.basename(repo) or ""
end

function M.is_cdp_buffer()
  local name = vim.api.nvim_buf_get_name(0)
  return CDP_MARKER ~= "" and name:find(CDP_MARKER, 1, true) ~= nil
end

function M.backend()
  if M.is_cdp_buffer() then
    return require("cdp")
  end
  return require("databricks")
end

function M.setup_sql_keymaps()
  local opts = { noremap = true, silent = true, buffer = true }
  local router = M

  vim.keymap.set("n", "<leader>db", function()
    if not router.backend().is_configured() then
      return
    end
    router.backend().execute_buffer()
  end, opts)

  vim.keymap.set("v", "<leader>db", function()
    if not router.backend().is_configured() then
      return
    end
    router.backend().execute_visual()
  end, opts)

  vim.keymap.set("n", "<leader>dc", function()
    if not router.backend().is_configured() then
      return
    end
    router.backend().toggle_sidebar()
  end, opts)

  local backend = router.backend()
  if not backend.is_configured() then
    return
  end
  if router.is_cdp_buffer() then
    backend.ensure_schemas_loaded()
  elseif not backend.schema_cache.loaded and #backend.schema_cache.tables == 0 then
    backend.refresh_schema()
  end
end

return M
