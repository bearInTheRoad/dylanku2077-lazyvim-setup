return {
  "Exafunction/codeium.nvim",
  event = "InsertEnter",
  config = function()
    require("codeium").setup({
      -- ✅ Only ghost-text
      virtual_text = {
        enabled = true,
        idle_delay = 10,
        map_keys = true, -- custom keymaps below
        key_bindings = {
          accept = "<leader>n",
          accept_word = "<leader>w",
          accept_line = "<leader>l",
          next = "<leader>j",
          prev = "<leader>k",
        },
      },

      -- ✅ Manual trigger only
      manual = true,

      -- ✅ Disable cmp popup mode
      enable_cmp_source = false,
    })
  end,
}
