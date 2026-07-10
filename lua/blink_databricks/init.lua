local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == "sql"
end

function source:get_trigger_characters()
  return { ".", "_" }
end

function source:get_completions(ctx, callback)
  local databricks = require("databricks")
  local cache = databricks.schema_cache

  if not cache.loaded and #cache.tables == 0 then
    callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = false })
    return function() end
  end

  local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
  local items = {}

  for _, tbl in ipairs(cache.tables) do
    table.insert(items, {
      label = tbl,
      kind = CompletionItemKind.Class,
      detail = "Table",
      labelDetails = { description = databricks.config.catalog },
      insertText = tbl,
    })
  end

  for tbl, cols in pairs(cache.columns) do
    for _, col in ipairs(cols) do
      table.insert(items, {
        label = col.name,
        kind = CompletionItemKind.Field,
        detail = col.type,
        labelDetails = { description = tbl },
        insertText = col.name,
      })
    end
  end

  -- if user typed "tablename." try to load columns for that table
  local line = ctx.line:sub(1, ctx.cursor[2])
  local prefix = line:match("([%w_]+%.[%w_]+)%.[%w_]*$")
  if prefix then
    for _, tbl in ipairs(cache.tables) do
      if tbl == prefix and not cache.columns[tbl] then
        databricks.load_columns_for_table(tbl)
        break
      end
    end
  end

  callback({ items = items, is_incomplete_forward = not cache.loaded, is_incomplete_backward = false })
  return function() end
end

return source
