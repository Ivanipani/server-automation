vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set("i", "<C-c>", "<Esc>")

vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist,
               {desc = "Open diagnostics [Q]uickfix list"})
vim.keymap.set("n", "<left>", "<cmd>echo 'Use h to move!!'<CR>")
vim.keymap.set("n", "<right>", "<cmd>echo 'Use l to move!!'<CR>")
vim.keymap.set("n", "<up>", "<cmd>echo 'Use k to move!!'<CR>")
vim.keymap.set("n", "<down>", "<cmd>echo 'Use j to move!!'<CR>")

vim.keymap.set("n", "<C-h>", "<C-w><C-h>", {desc = "Move to the left window"})
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", {desc = "Move to the lower window"})
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", {desc = "Move to the upper window"})
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", {desc = "Move to the right window"})

vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist,
               {desc = "Open diagnostics [Q]uickfix list"})

vim.keymap.set("n", "<C-p>", "<cmd>Telescope find_files<CR>",
               {desc = "Find files"})
vim.keymap.set("n", "<leader>j", "<cmd>Telescope jumplist<CR>",
               {desc = "Find jumplist"})
vim.keymap.set("n", "<C-i>", "<C-o>", {desc = "Go back one jump"})
vim.keymap.set("n", "<C-o>", "<C-i>", {desc = "Go forward one jump"})

vim.keymap.set("v", "J", ":m >+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m <-2<CR>gv=gv")
vim.keymap.set("n", "<J>", "mjZ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>`", "\"_dP")

vim.keymap.set("v", "<leader>y", "\"+y", {desc = "Yank to system clipboard"})
vim.keymap.set("n", "<leader>Y", "\"+y", {desc = "Yank to system clipboard"})
vim.keymap.set("n", "Q", "<nop>")
