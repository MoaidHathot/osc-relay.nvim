-- Auto-bootstrap with safe defaults so the plugin works without explicit setup.
if vim.g.loaded_osc_relay then return end
vim.g.loaded_osc_relay = 1

if vim.fn.has("nvim-0.10") ~= 1 then return end

require("osc-relay").setup({})
