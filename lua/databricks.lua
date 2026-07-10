local M = {}

local env = require("config.env")

M.config = {
  profile = env.get("DATABRICKS_PROFILE", ""),
  warehouse_id = env.get("DATABRICKS_WAREHOUSE_ID", ""),
  catalog = env.get("DATABRICKS_CATALOG", ""),
}

--- True when all Databricks env vars are set.
function M.is_configured()
  return M.config.profile ~= "" and M.config.warehouse_id ~= "" and M.config.catalog ~= ""
end

M.schema_cache = {
  schemas = {},
  tables = {},
  columns = {},
  loaded = false,
}

M.result_buf = -1
M.result_win = -1

M.sidebar = {
  buf = -1,
  win = -1,
  tree = {},
  expanded = {},
}

local function run_statement(sql, callback)
  local json_payload = vim.fn.json_encode({
    warehouse_id = M.config.warehouse_id,
    statement = sql,
    wait_timeout = "30s",
  })

  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "w")
  f:write(json_payload)
  f:close()

  local stdout_chunks = {}
  vim.fn.jobstart({
    "databricks", "api", "post", "/api/2.0/sql/statements",
    "--profile", M.config.profile,
    "--json", "@" .. tmp,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_chunks, data)
      end
    end,
    on_exit = function(_, exit_code)
      vim.fn.delete(tmp)
      vim.schedule(function()
        if exit_code ~= 0 then
          vim.notify("Databricks query failed (exit " .. exit_code .. ")", vim.log.levels.ERROR)
          return
        end
        while #stdout_chunks > 0 and stdout_chunks[#stdout_chunks] == "" do
          table.remove(stdout_chunks)
        end
        local raw = table.concat(stdout_chunks, "\n")
        if raw == "" then
          vim.notify("Empty response from Databricks", vim.log.levels.ERROR)
          return
        end
        local ok, result = pcall(vim.fn.json_decode, raw)
        if not ok then
          vim.notify("Failed to parse Databricks response: " .. raw:sub(1, 200), vim.log.levels.ERROR)
          return
        end
        callback(result)
      end)
    end,
  })
end

local function format_table(result)
  if not result or not result.manifest or not result.result then
    if result and result.status and result.status.error then
      return { "ERROR: " .. (result.status.error.message or "unknown error") }
    end
    return { "No results returned." }
  end

  local columns = result.manifest.schema.columns
  local raw_data = result.result.data_array
  local data = (type(raw_data) == "table") and raw_data or {}

  local headers = {}
  for _, col in ipairs(columns) do
    table.insert(headers, col.name)
  end

  local widths = {}
  for i, h in ipairs(headers) do
    widths[i] = #h
  end
  for _, row in ipairs(data) do
    for i, val in ipairs(row) do
      local s = (type(val) == "string") and val or "NULL"
      widths[i] = math.max(widths[i] or 0, #s)
    end
  end

  local lines = {}
  local header_line = ""
  local sep_line = ""
  for i, h in ipairs(headers) do
    local padded = h .. string.rep(" ", widths[i] - #h)
    header_line = header_line .. (i > 1 and " | " or "") .. padded
    sep_line = sep_line .. (i > 1 and "-+-" or "") .. string.rep("-", widths[i])
  end
  table.insert(lines, header_line)
  table.insert(lines, sep_line)

  for _, row in ipairs(data) do
    local line = ""
    for i, val in ipairs(row) do
      local s = (type(val) == "string") and val or "NULL"
      local padded = s .. string.rep(" ", widths[i] - #s)
      line = line .. (i > 1 and " | " or "") .. padded
    end
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(lines, string.format("(%d rows)", #data))
  return lines
end

local function show_in_split(lines, title)
  if not vim.api.nvim_buf_is_valid(M.result_buf) then
    M.result_buf = vim.api.nvim_create_buf(false, true)
  end

  local flat = {}
  for _, line in ipairs(lines) do
    for sub in (line .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(flat, sub)
    end
  end

  vim.api.nvim_buf_set_option(M.result_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, flat)
  vim.api.nvim_buf_set_option(M.result_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(M.result_buf, "buftype", "nofile")
  pcall(vim.api.nvim_buf_set_name, M.result_buf, title or "[Databricks Result]")

  -- Apply highlights to the result buffer
  local ns = vim.api.nvim_create_namespace("databricks_result")
  vim.api.nvim_buf_clear_namespace(M.result_buf, ns, 0, -1)
  for i, line in ipairs(flat) do
    local row = i - 1
    if i == 1 then
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DatabricksResultHeader", row, 0, -1)
    elseif line:match("^%-") then
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DatabricksResultSep", row, 0, -1)
    elseif line:match("^%(") then
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DatabricksResultCount", row, 0, -1)
    elseif line:match("^ERROR:") then
      vim.api.nvim_buf_add_highlight(M.result_buf, ns, "ErrorMsg", row, 0, -1)
    else
      -- highlight NULL values
      local start = 0
      while true do
        local s, e = line:find("NULL", start + 1, true)
        if not s then break end
        vim.api.nvim_buf_add_highlight(M.result_buf, ns, "DatabricksResultNull", row, s - 1, e)
        start = e
      end
    end
  end

  if not vim.api.nvim_win_is_valid(M.result_win) then
    local current_win = vim.api.nvim_get_current_win()
    vim.cmd("botright split")
    M.result_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(M.result_win, math.min(#flat + 1, 20))
    vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
    vim.api.nvim_set_current_win(current_win)
  else
    vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
    vim.api.nvim_win_set_height(M.result_win, math.min(#flat + 1, 20))
  end
end

-- Query execution

function M.execute_query(sql)
  vim.notify("Running query on Databricks...", vim.log.levels.INFO)
  run_statement(sql, function(result)
    local lines = format_table(result)
    show_in_split(lines, "[Databricks Result]")
  end)
end

local function split_queries(text)
  local queries = {}
  for q in (text .. ";"):gmatch("(.-);") do
    local trimmed = q:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      table.insert(queries, trimmed)
    end
  end
  return queries
end

function M.execute_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local full = table.concat(lines, "\n")
  local queries = split_queries(full)

  if #queries <= 1 then
    M.execute_query(queries[1] or full)
    return
  end

  local display = {}
  for i, q in ipairs(queries) do
    local preview = q:gsub("%s+", " ")
    if #preview > 60 then
      preview = preview:sub(1, 57) .. "..."
    end
    table.insert(display, string.format("[%d] %s", i, preview))
  end

  vim.ui.select(display, { prompt = "Select query to run:" }, function(_, idx)
    if idx then
      M.execute_query(queries[idx])
    end
  end)
end

function M.execute_visual()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then return end
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end
  local sql = table.concat(lines, "\n")
  M.execute_query(sql)
end

-- Highlights

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "DatabricksCatalog", { fg = "#e0af68", bold = true })
  hl(0, "DatabricksSchema", { fg = "#7aa2f7", bold = true })
  hl(0, "DatabricksTable", { fg = "#9ece6a" })
  hl(0, "DatabricksColumn", { fg = "#c0caf5" })
  hl(0, "DatabricksType", { fg = "#bb9af7", italic = true })
  hl(0, "DatabricksLoading", { fg = "#565f89", italic = true })
  hl(0, "DatabricksIcon", { fg = "#ff9e64" })
  hl(0, "DatabricksResultHeader", { fg = "#7aa2f7", bold = true })
  hl(0, "DatabricksResultSep", { fg = "#565f89" })
  hl(0, "DatabricksResultRow", { fg = "#c0caf5" })
  hl(0, "DatabricksResultCount", { fg = "#565f89", italic = true })
  hl(0, "DatabricksResultNull", { fg = "#565f89", italic = true })
end

-- Sidebar catalogue browser

local function sidebar_render()
  local sb = M.sidebar
  if not vim.api.nvim_buf_is_valid(sb.buf) then return end

  local lines = {}
  local line_map = {}
  local highlights = {}

  local catalog_line = "  " .. M.config.catalog
  table.insert(lines, catalog_line)
  table.insert(line_map, { type = "catalog" })
  table.insert(highlights, { line = #lines - 1, col = 0, len = 3, hl = "DatabricksIcon" })
  table.insert(highlights, { line = #lines - 1, col = 4, len = #M.config.catalog, hl = "DatabricksCatalog" })

  for _, schema in ipairs(M.schema_cache.schemas) do
    local schema_expanded = sb.expanded["s:" .. schema]
    local icon = schema_expanded and " " or " "
    local schema_line = "  " .. icon .. " " .. schema
    table.insert(lines, schema_line)
    table.insert(line_map, { type = "schema", schema = schema })
    table.insert(highlights, { line = #lines - 1, col = 2, len = #icon, hl = "DatabricksIcon" })
    table.insert(highlights, { line = #lines - 1, col = 2 + #icon + 1, len = #schema, hl = "DatabricksSchema" })

    if schema_expanded then
      local schema_tables = {}
      for _, tbl in ipairs(M.schema_cache.tables) do
        local s, t = tbl:match("^(.-)%.(.+)$")
        if s == schema then
          table.insert(schema_tables, t)
        end
      end
      table.sort(schema_tables)

      if #schema_tables == 0 then
        table.insert(lines, "      (loading...)")
        table.insert(line_map, { type = "loading" })
        table.insert(highlights, { line = #lines - 1, col = 0, len = 30, hl = "DatabricksLoading" })
      else
        for _, tbl in ipairs(schema_tables) do
          local qualified = schema .. "." .. tbl
          local tbl_expanded = sb.expanded["t:" .. qualified]
          local tbl_icon = tbl_expanded and " " or " "
          local tbl_line = "    " .. tbl_icon .. " " .. tbl
          table.insert(lines, tbl_line)
          table.insert(line_map, { type = "table", schema = schema, table = tbl, qualified = qualified })
          table.insert(highlights, { line = #lines - 1, col = 4, len = #tbl_icon, hl = "DatabricksIcon" })
          table.insert(highlights, { line = #lines - 1, col = 4 + #tbl_icon + 1, len = #tbl, hl = "DatabricksTable" })

          if tbl_expanded then
            local cols = M.schema_cache.columns[qualified]
            if not cols then
              table.insert(lines, "        (loading...)")
              table.insert(line_map, { type = "loading" })
              table.insert(highlights, { line = #lines - 1, col = 0, len = 30, hl = "DatabricksLoading" })
            else
              for _, col in ipairs(cols) do
                local col_line = "        " .. col.name .. "  " .. col.type
                table.insert(lines, col_line)
                table.insert(line_map, { type = "column", schema = schema, table = tbl, column = col })
                table.insert(highlights, { line = #lines - 1, col = 8, len = #col.name, hl = "DatabricksColumn" })
                table.insert(highlights, { line = #lines - 1, col = 8 + #col.name + 2, len = #col.type, hl = "DatabricksType" })
              end
            end
          end
        end
      end
    end
  end

  sb.line_map = line_map
  vim.api.nvim_buf_set_option(sb.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(sb.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(sb.buf, "modifiable", false)

  local ns = vim.api.nvim_create_namespace("databricks_sidebar")
  vim.api.nvim_buf_clear_namespace(sb.buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(sb.buf, ns, h.hl, h.line, h.col, h.col + h.len)
  end
end

local function sidebar_action()
  local sb = M.sidebar
  if not sb.line_map then return end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local entry = sb.line_map[row]
  if not entry then return end

  if entry.type == "schema" then
    local key = "s:" .. entry.schema
    if sb.expanded[key] then
      sb.expanded[key] = nil
    else
      sb.expanded[key] = true
      local has_tables = false
      for _, tbl in ipairs(M.schema_cache.tables) do
        if tbl:match("^" .. vim.pesc(entry.schema) .. "%.") then
          has_tables = true
          break
        end
      end
      if not has_tables then
        local sql = string.format("SHOW TABLES IN %s.%s", M.config.catalog, entry.schema)
        run_statement(sql, function(result)
          if result and result.result then
            for _, r in ipairs(result.result.data_array or {}) do
              local tbl_name = r[2] or r[1]
              if tbl_name then
                table.insert(M.schema_cache.tables, entry.schema .. "." .. tbl_name)
              end
            end
          end
          sidebar_render()
        end)
      end
    end
    sidebar_render()

  elseif entry.type == "table" then
    local key = "t:" .. entry.qualified
    if sb.expanded[key] then
      sb.expanded[key] = nil
    else
      sb.expanded[key] = true
      if not M.schema_cache.columns[entry.qualified] then
        M.load_columns_for_table(entry.qualified, function()
          sidebar_render()
        end)
      end
    end
    sidebar_render()
  end
end

function M.toggle_sidebar()
  local sb = M.sidebar

  if vim.api.nvim_win_is_valid(sb.win) then
    vim.api.nvim_win_close(sb.win, true)
    sb.win = -1
    return
  end

  if not vim.api.nvim_buf_is_valid(sb.buf) then
    sb.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(sb.buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(sb.buf, "filetype", "databricks_catalog")
    pcall(vim.api.nvim_buf_set_name, sb.buf, "[Databricks Catalog]")
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "<CR>", "", {
      noremap = true, silent = true,
      callback = sidebar_action,
    })
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "o", "", {
      noremap = true, silent = true,
      callback = sidebar_action,
    })
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "q", "", {
      noremap = true, silent = true,
      callback = function() M.toggle_sidebar() end,
    })
  end

  vim.cmd("topleft vsplit")
  sb.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(sb.win, 40)
  vim.api.nvim_win_set_buf(sb.win, sb.buf)
  vim.api.nvim_win_set_option(sb.win, "number", false)
  vim.api.nvim_win_set_option(sb.win, "relativenumber", false)
  vim.api.nvim_win_set_option(sb.win, "signcolumn", "no")
  vim.api.nvim_win_set_option(sb.win, "winfixwidth", true)

  if #M.schema_cache.schemas == 0 then
    local sql = string.format("SHOW SCHEMAS IN %s", M.config.catalog)
    run_statement(sql, function(result)
      if result and result.result then
        for _, row in ipairs(result.result.data_array or {}) do
          local name = row[1] or ""
          if name ~= "" and name ~= "information_schema" then
            table.insert(M.schema_cache.schemas, name)
          end
        end
        table.sort(M.schema_cache.schemas)
      end
      sidebar_render()
    end)
  else
    sidebar_render()
  end

  vim.cmd("wincmd p")
end

-- Schema cache

function M.refresh_schema()
  vim.notify("Refreshing Databricks schema cache...", vim.log.levels.INFO)
  M.schema_cache = { schemas = {}, tables = {}, columns = {}, loaded = false }

  local sql = string.format("SHOW SCHEMAS IN %s", M.config.catalog)
  run_statement(sql, function(schema_result)
    if not schema_result or not schema_result.result then
      vim.notify("Failed to fetch schemas", vim.log.levels.ERROR)
      return
    end

    for _, row in ipairs(schema_result.result.data_array or {}) do
      local schema_name = row[1] or ""
      if schema_name ~= "" and schema_name ~= "information_schema" then
        table.insert(M.schema_cache.schemas, schema_name)
      end
    end
    table.sort(M.schema_cache.schemas)

    local pending = #M.schema_cache.schemas
    if pending == 0 then
      M.schema_cache.loaded = true
      vim.notify("Schema cache loaded (0 schemas)", vim.log.levels.INFO)
      return
    end

    for _, schema in ipairs(M.schema_cache.schemas) do
      local tbl_sql = string.format("SHOW TABLES IN %s.%s", M.config.catalog, schema)
      run_statement(tbl_sql, function(tbl_result)
        if tbl_result and tbl_result.result then
          for _, row in ipairs(tbl_result.result.data_array or {}) do
            local tbl_name = row[2] or row[1]
            if tbl_name then
              table.insert(M.schema_cache.tables, schema .. "." .. tbl_name)
            end
          end
        end

        pending = pending - 1
        if pending == 0 then
          M.schema_cache.loaded = true
          vim.notify(
            string.format("Schema cache loaded (%d tables across %d schemas)",
              #M.schema_cache.tables, #M.schema_cache.schemas),
            vim.log.levels.INFO
          )
          sidebar_render()
        end
      end)
    end
  end)
end

function M.load_columns_for_table(qualified_table, callback)
  if M.schema_cache.columns[qualified_table] then
    if callback then callback() end
    return
  end

  local desc_sql = string.format("DESCRIBE TABLE %s.%s", M.config.catalog, qualified_table)
  run_statement(desc_sql, function(desc_result)
    if desc_result and desc_result.result then
      M.schema_cache.columns[qualified_table] = {}
      for _, col_row in ipairs(desc_result.result.data_array or {}) do
        local col_name = col_row[1] or ""
        if col_name ~= "" and not col_name:match("^#") then
          table.insert(M.schema_cache.columns[qualified_table], {
            name = col_name,
            type = col_row[2] or "",
            description = col_row[3] or "",
          })
        end
      end
    end
    if callback then callback() end
  end)
end

-- Setup

function M.setup()
  setup_highlights()

  if not M.is_configured() then
    return
  end

  vim.api.nvim_create_user_command("DatabricksRefreshSchema", function()
    M.refresh_schema()
  end, {})

  vim.api.nvim_create_user_command("DatabricksLoadTable", function(opts)
    local tbl = opts.args
    if not tbl or tbl == "" then
      vim.notify("Usage: :DatabricksLoadTable schema.table", vim.log.levels.WARN)
      return
    end
    M.load_columns_for_table(tbl, function()
      vim.notify("Columns loaded for " .. tbl, vim.log.levels.INFO)
    end)
  end, { nargs = 1 })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    callback = function()
      require("sql_router").setup_sql_keymaps()
    end,
  })
end

return M
