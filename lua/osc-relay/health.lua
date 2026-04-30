local M = {}

local function start(report) return report.start or vim.health.start end
local function ok(report) return report.ok or vim.health.ok end
local function warn(report) return report.warn or vim.health.warn end
local function err(report) return report.error or vim.health.error end

function M.check()
  local h = vim.health
  start(h)("osc-relay.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    ok(h)("Neovim " .. tostring(vim.version()))
  else
    err(h)("Neovim >= 0.10 required (TermRequest event)")
  end

  if vim.uv and vim.uv.fs_write then
    ok(h)("vim.uv.fs_write available")
  else
    warn(h)("vim.uv.fs_write missing; will fall back to io.stderr")
  end

  local mux = (vim.env.TMUX and "tmux") or (vim.env.ZELLIJ and "zellij") or "none"
  ok(h)("multiplexer: " .. mux)

  local Config = require("osc-relay.config")
  ok(h)("config: " .. vim.inspect(Config.current))

  local has = false
  for _, a in ipairs(vim.api.nvim_get_autocmds({ event = "TermRequest" })) do
    if a.group_name == "OscRelay" then has = true; break end
  end
  if has then
    ok(h)("TermRequest autocmd registered")
  else
    warn(h)("TermRequest autocmd not registered (call require('osc-relay').setup())")
  end
end

return M
