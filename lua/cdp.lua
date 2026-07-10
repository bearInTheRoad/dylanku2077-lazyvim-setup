local M = {}

local env = require("config.env")

M.config = {
  repo = env.get("CDP_REPO", ""),
  database = env.get("CDP_DATABASE", "dwh"),
}

--- True when CDP_REPO is set.
function M.is_configured()
  return M.config.repo ~= ""
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

local function first_column_values(result)
  if not result or not result.rows then
    return {}
  end
  local values = {}
  for _, row in ipairs(result.rows) do
    if row[1] and row[1] ~= "" then
      table.insert(values, row[1])
    end
  end
  return values
end

local function run_cli(args, callback)
  local cmd = string.format(
    "cd %s && poetry run python tools/impala_cli.py %s",
    vim.fn.shellescape(M.config.repo),
    args
  )

  local stdout_chunks = {}
  vim.fn.jobstart({ "bash", "-lc", cmd }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_chunks, data)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        while #stdout_chunks > 0 and stdout_chunks[#stdout_chunks] == "" do
          table.remove(stdout_chunks)
        end
        local raw = table.concat(stdout_chunks, "\n")
        if exit_code ~= 0 and raw == "" then
          vim.notify("Impala CLI failed (exit " .. exit_code .. ")", vim.log.levels.ERROR)
          return
        end
        if raw == "" then
          vim.notify("Empty response from Impala CLI", vim.log.levels.ERROR)
          return
        end
        local ok, result = pcall(vim.fn.json_decode, raw)
        if not ok then
          vim.notify("Failed to parse Impala response: " .. raw:sub(1, 200), vim.log.levels.ERROR)
          return
        end
        if not result.ok then
          vim.notify(result.error or "Impala query failed", vim.log.levels.ERROR)
          return
        end
        callback(result)
      end)
    end,
  })
end

local function run_sql_file(sql, callback)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(sql, "\n", { plain = true }), tmp)
  run_cli("run --sql-file " .. vim.fn.shellescape(tmp), function(result)
    vim.fn.delete(tmp)
    callback(result)
  end)
end

local function format_table(result)
  if not result or not result.columns then
    return { "No results returned." }
  end

  if result.error then
    return { "ERROR: " .. result.error }
  end

  local headers = result.columns
  local data = result.rows or {}

  local widths = {}
  for i, h in ipairs(headers) do
    widths[i] = #tostring(h)
  end
  for _, row in ipairs(data) do
    for i, val in ipairs(row) do
      local s = (val == vim.NIL or val == nil) and "NULL" or tostring(val)
      widths[i] = math.max(widths[i] or 0, #s)
    end
  end

  local lines = {}
  local header_line = ""
  local sep_line = ""
  for i, h in ipairs(headers) do
    local hs = tostring(h)
    local padded = hs .. string.rep(" ", widths[i] - #hs)
    header_line = header_line .. (i > 1 and " | " or "") .. padded
    sep_line = sep_line .. (i > 1 and "-+-" or "") .. string.rep("-", widths[i])
  end
  table.insert(lines, header_line)
  table.insert(lines, sep_line)

  for _, row in ipairs(data) do
    local line = ""
    for i, val in ipairs(row) do
      local s = (val == vim.NIL or val == nil) and "NULL" or tostring(val)
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
  pcall(vim.api.nvim_buf_set_name, M.result_buf, title or "[Impala Result]")

  local ns = vim.api.nvim_create_namespace("cdp_result")
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
      local start = 0
      while true do
        local s, e = line:find("NULL", start + 1, true)
        if not s then
          break
        end
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

function M.execute_query(sql)
  vim.notify("Running query on Impala...", vim.log.levels.INFO)
  run_sql_file(sql, function(result)
    show_in_split(format_table(result), "[Impala Result]")
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
  if #lines == 0 then
    return
  end
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end
  M.execute_query(table.concat(lines, "\n"))
end

local function sidebar_render()
  local sb = M.sidebar
  if not vim.api.nvim_buf_is_valid(sb.buf) then
    return
  end

  local lines = {}
  local line_map = {}
  local highlights = {}

  local root_line = "  CDP Impala"
  table.insert(lines, root_line)
  table.insert(line_map, { type = "root" })
  table.insert(highlights, { line = #lines - 1, col = 2, len = 2, hl = "DatabricksIcon" })
  table.insert(highlights, { line = #lines - 1, col = 4, len = #root_line - 4, hl = "DatabricksCatalog" })

  for _, schema in ipairs(M.schema_cache.schemas) do
    local schema_expanded = sb.expanded["s:" .. schema]
    local icon = schema_expanded and "▼" or "▶"
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
          local tbl_icon = tbl_expanded and "▼" or "▶"
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
                table.insert(highlights, {
                  line = #lines - 1,
                  col = 8 + #col.name + 2,
                  len = #col.type,
                  hl = "DatabricksType",
                })
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

  local ns = vim.api.nvim_create_namespace("cdp_sidebar")
  vim.api.nvim_buf_clear_namespace(sb.buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(sb.buf, ns, h.hl, h.line, h.col, h.col + h.len)
  end
end

local function sidebar_action()
  local sb = M.sidebar
  if not sb.line_map then
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local entry = sb.line_map[row]
  if not entry then
    return
  end

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
        run_cli("tables --database " .. vim.fn.shellescape(entry.schema), function(result)
          for _, name in ipairs(first_column_values(result)) do
            table.insert(M.schema_cache.tables, entry.schema .. "." .. name)
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
    pcall(vim.api.nvim_buf_set_name, sb.buf, "[Impala Catalog]")
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "<CR>", "", {
      noremap = true,
      silent = true,
      callback = sidebar_action,
    })
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "o", "", {
      noremap = true,
      silent = true,
      callback = sidebar_action,
    })
    vim.api.nvim_buf_set_keymap(sb.buf, "n", "q", "", {
      noremap = true,
      silent = true,
      callback = function()
        M.toggle_sidebar()
      end,
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
    run_cli("schemas", function(result)
      M.schema_cache.schemas = first_column_values(result)
      table.sort(M.schema_cache.schemas)
      sidebar_render()
    end)
  else
    sidebar_render()
  end

  vim.cmd("wincmd p")
end

function M.refresh_schema()
  vim.notify("Refreshing Impala schema cache...", vim.log.levels.INFO)
  M.schema_cache = { schemas = {}, tables = {}, columns = {}, loaded = false }

  run_cli("schemas", function(schema_result)
    M.schema_cache.schemas = first_column_values(schema_result)
    table.sort(M.schema_cache.schemas)

    local pending = #M.schema_cache.schemas
    if pending == 0 then
      M.schema_cache.loaded = true
      vim.notify("Schema cache loaded (0 databases)", vim.log.levels.INFO)
      return
    end

    for _, schema in ipairs(M.schema_cache.schemas) do
      run_cli("tables --database " .. vim.fn.shellescape(schema), function(tbl_result)
        for _, name in ipairs(first_column_values(tbl_result)) do
          table.insert(M.schema_cache.tables, schema .. "." .. name)
        end

        pending = pending - 1
        if pending == 0 then
          M.schema_cache.loaded = true
          vim.notify(
            string.format(
              "Schema cache loaded (%d tables across %d databases)",
              #M.schema_cache.tables,
              #M.schema_cache.schemas
            ),
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
    if callback then
      callback()
    end
    return
  end

  run_cli("describe --table " .. vim.fn.shellescape(qualified_table), function(desc_result)
    M.schema_cache.columns[qualified_table] = {}
    for _, row in ipairs(desc_result.rows or {}) do
      local col_name = row[1] and tostring(row[1]) or ""
      if col_name ~= "" and not col_name:match("^#") then
        table.insert(M.schema_cache.columns[qualified_table], {
          name = col_name,
          type = row[2] and tostring(row[2]) or "",
          description = row[3] and tostring(row[3]) or "",
        })
      end
    end
    if callback then
      callback()
    end
  end)
end

function M.ensure_schemas_loaded()
  if #M.schema_cache.schemas > 0 then
    return
  end
  run_cli("schemas", function(result)
    M.schema_cache.schemas = first_column_values(result)
    table.sort(M.schema_cache.schemas)
  end)
end

function M.setup()
  if not M.is_configured() then
    return
  end

  vim.api.nvim_create_user_command("CdpRefreshSchema", function()
    M.refresh_schema()
  end, {})

  vim.api.nvim_create_user_command("CdpLoadTable", function(opts)
    local tbl = opts.args
    if not tbl or tbl == "" then
      vim.notify("Usage: :CdpLoadTable db.table", vim.log.levels.WARN)
      return
    end
    M.load_columns_for_table(tbl, function()
      vim.notify("Columns loaded for " .. tbl, vim.log.levels.INFO)
    end)
  end, { nargs = 1 })
end

return M
