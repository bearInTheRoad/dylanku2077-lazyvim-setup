return {
  "saghen/blink.cmp",
  opts = {
    completion = {
      menu = {
        draw = {
          columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },
        },
      },
    },
    sources = {
      default = { "databricks" },
      providers = {
        databricks = {
          name = "databricks",
          module = "blink_databricks",
          fallbacks = {},
          score_offset = 10,
          enabled = function()
            return vim.bo.filetype == "sql"
          end,
        },
      },
    },
  },
}
