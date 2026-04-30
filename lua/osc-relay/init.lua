-- osc-relay.nvim
-- Forward OSC sequences emitted by :terminal children out to the host
-- terminal, so e.g. Windows Terminal tabs reflect inner-process state.

local Config = require("osc-relay.config")
local Relay = require("osc-relay.relay")
local Sink = require("osc-relay.sink")

local M = {}

local SUBCMDS = { "status", "enable", "disable", "reset", "send" }

local function register_command()
  if vim.fn.exists(":OscRelay") == 2 then return end
  vim.api.nvim_create_user_command("OscRelay", function(opts)
    local sub = opts.fargs[1] or "status"
    if sub == "status" then
      local s = M.status()
      vim.notify(vim.inspect(s), vim.log.levels.INFO)
    elseif sub == "enable" then
      M.enable()
      vim.notify("osc-relay: enabled", vim.log.levels.INFO)
    elseif sub == "disable" then
      M.disable()
      vim.notify("osc-relay: disabled", vim.log.levels.INFO)
    elseif sub == "reset" then
      Sink.write("\27]9;4;0;0\27\\", Config.current.multiplex)
      vim.notify("osc-relay: progress bar cleared", vim.log.levels.INFO)
    elseif sub == "send" then
      local bytes = table.concat(opts.fargs, " ", 2)
      if bytes == "" then
        vim.notify("osc-relay: send requires bytes", vim.log.levels.ERROR)
        return
      end
      M.send(bytes)
    else
      vim.notify("osc-relay: unknown subcommand: " .. sub, vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    desc = "osc-relay control",
    complete = function(arglead, line)
      if line:match("^%s*OscRelay%s+%S*$") then
        return vim.tbl_filter(function(c) return c:find("^" .. arglead) end, SUBCMDS)
      end
      return {}
    end,
  })
end

---@param opts? OscRelay.Config|table
function M.setup(opts)
  Config.merge(opts)
  Relay.detach()
  if Config.current.enabled then
    Relay.attach()
  end
  register_command()
end

---@param buf? integer  default: global enable
function M.enable(buf)
  if buf then
    Relay.buf_enabled[buf] = true
  else
    Config.current.enabled = true
    Relay.attach()
  end
end

---@param buf? integer  default: global disable
function M.disable(buf)
  if buf then
    Relay.buf_enabled[buf] = false
  else
    Config.current.enabled = false
    Relay.detach()
  end
end

---Manually relay raw bytes to the host terminal.
---@param bytes string
function M.send(bytes)
  Sink.write(bytes, Config.current.multiplex)
end

---@return table
function M.status()
  return {
    enabled = Config.current.enabled,
    config = vim.deepcopy(Config.current),
    last = vim.deepcopy(Relay.last),
    active_buf = Relay.active_buf,
    buf_overrides = vim.deepcopy(Relay.buf_enabled),
  }
end

return M
