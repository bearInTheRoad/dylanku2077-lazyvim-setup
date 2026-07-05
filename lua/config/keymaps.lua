-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.g.mapleader = " "
vim.g.maplocalleader = " "

map = vim.keymap.set

-- 复用 opt 参数
local opt = { noremap = true, silent = true }

-- 窗口管理交给 LazyVim 默认快捷键: <leader>- <leader>| <leader>wd <C-w>*
-- 窗口之间跳转
map("n", "<leader>h", "<C-w>h", opt)
map("n", "<leader>j", "<C-w>j", opt)
map("n", "<leader>k", "<C-w>k", opt)
map("n", "<leader>l", "<C-w>l", opt)

-- 比例控制 (LazyVim 默认已有 <C-Up/Down/Left/Right> 微调)
map("n", "<C-Left>", ":vertical resize -2<CR>", opt)
map("n", "<C-Right>", ":vertical resize +2<CR>", opt)
map("n", "<C-Down>", ":resize +2<CR>", opt)
map("n", "<C-Up>", ":resize -2<CR>", opt)

-- Terminal相关
map("n", "<leader>t", ":sp | terminal<CR>", opt)
map("n", "<leader>vt", ":vsp | terminal<CR>", opt)
-- Exit terminal mode and return to normal mode
map("t", "<Esc>", "<C-\\><C-n>", opt)
-- 在terminal模式下，清理一个单词
map("t", "<C-w>", "[[<C-\\><C-n><C-w>. ]]", opt)
-- 在terminal模式下，清理一整行
map("t", "<C-u>", "[[C-u>]]", opt)

-- 上下滚动浏览
map("n", "<C-j>", "4j", opt)
map("n", "<C-k>", "4k", opt)
-- ctrl u / ctrl + d  只移动9行，默认移动半屏
map("n", "<C-u>", "9k", opt)
map("n", "<C-d>", "9j", opt)

--快速粘贴到系统剪贴板
map("v", "<leader>y", [["+y]], opt)

--回到上次编辑的位置
map("n", "<leader>o", "<C-o>", opt)

--粘贴到下面一行
map("n", "<leader>p", ":pu<CR>", opt)
-- 粘贴到上面一行
map("n", "<leader>P", "O<Esc>p", opt)

--回到本行的第一个字符
map("n", "H", "^", opt)
map("v", "H", "^", opt)
--回到本行的最后一个字符
map("n", "L", "g_", opt)
map("v", "L", "g_", opt)

--展示行信息，包括错误
map("n", "<leader>ud", vim.diagnostic.open_float, opt)

-- 插入 TODO 时间戳行 (normal 模式 <leader>T)
local function insert_timestamp()
  local ts = os.date("%Y-%m-%d %H:%M:%S")
  -- 根据当前文件的注释风格自动选择注释符号
  local cs = vim.bo.commentstring
  local comment = cs:match("^(.-)%%s")
  if comment == nil or comment == "" then comment = "--" end
  comment = comment:gsub("%s+$", "")
  local line = ("%s TODO: [%s] "):format(comment, ts)
  local row = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_lines(0, row, row, false, { line })
  vim.api.nvim_win_set_cursor(0, { row + 1, #line })
  vim.cmd("startinsert!")
end
map("n", "<leader>T", insert_timestamp, opt)
vim.api.nvim_create_user_command("Timestamp", insert_timestamp, { desc = "Insert current timestamp" })
