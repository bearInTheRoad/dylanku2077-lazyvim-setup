return {
  {
    "Exafunction/codeium.nvim",
    opts = {
      enable_chat = true,
    },
    config = function(_, opts)
      require("codeium").setup(opts)
      
      local last_tab_time = 0
      local tab_threshold = 300
      
      vim.keymap.set('i', '<Tab>', function()
        local current_time = vim.uv.now()
        local time_diff = current_time - last_tab_time
        local codeium = require("codeium.virtual_text")
        
        if time_diff < tab_threshold and codeium.get_current_completion_item() ~= nil then
          last_tab_time = 0
          require("codeium.virtual_text").accept()
        else
          last_tab_time = current_time
          if vim.fn.pumvisible() == 1 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-n>', true, false, true), 'n', false)
          else
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Tab>', true, false, true), 'n', false)
          end
        end
      end, { silent = true })
    end,
  },
}
