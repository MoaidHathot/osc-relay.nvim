local Config = require("osc-relay.config")
local Filter = require("osc-relay.filter")
local Sink = require("osc-relay.sink")

local M = {}

local AUGROUP = "OscRelay"
local OSC_RESET = "\27]9;4;0;0\27\\"

---@type table<integer, boolean> per-buffer override
M.buf_enabled = {}
---@type table<integer, string> last selector relayed from each buffer
M.last = {}
---@type integer? buffer that emitted the most recent forwarded sequence
M.active_buf = nil

---@param buf integer
---@return boolean
local function in_scope(buf)
  local cfg = Config.current
  local scope = cfg.scope
  if type(scope) == "function" then return scope(buf) == true end
  if scope == "all" then return true end
  if scope == "focused" then
    return vim.api.nvim_get_current_buf() == buf
  end
  return false
end

---@param buf integer
---@return boolean
local function buf_active(buf)
  if M.buf_enabled[buf] == false then return false end
  return Config.current.enabled
end

---@param seq string
---@param buf integer
---@param sel string
local function dispatch(seq, buf, sel)
  Sink.write(seq, Config.current.multiplex)
  M.last[buf] = sel
  M.active_buf = buf
  if Config.current.notify then
    pcall(vim.api.nvim_exec_autocmds, "User", {
      pattern = "OscRelay",
      data = { selector = sel, sequence = seq, buf = buf },
    })
  end
  if Config.current.debug then
    vim.schedule(function()
      vim.notify(("[osc-relay] forwarded %s from buf %d"):format(sel, buf), vim.log.levels.DEBUG)
    end)
  end
end

local function on_term_request(ev)
  local buf = ev.buf
  if not buf_active(buf) then return end
  if not in_scope(buf) then return end
  local data = ev.data or {}
  local seq = data.sequence
  if type(seq) ~= "string" or seq == "" then return end
  local pass, sel = Filter.check(seq, Config.current.allow, Config.current.deny)
  if not pass or not sel then return end
  -- Re-attach terminator: TermRequest strips it from `sequence` on some builds;
  -- on others it includes it. Normalize: ensure ST suffix.
  if not seq:find("\27\\$") and not seq:find("\7$") then
    seq = seq .. "\27\\"
  end
  -- Ensure ESC ] prefix
  if not seq:find("^\27%]") then
    seq = "\27]" .. seq
  end
  dispatch(seq, buf, sel)
end

local function on_reset(ev)
  -- Only reset if this buffer was the last forwarder, or on global exit.
  if ev.event == "VimLeavePre" or M.active_buf == ev.buf or M.active_buf == nil then
    Sink.write(OSC_RESET, Config.current.multiplex)
    M.last[ev.buf] = nil
    if M.active_buf == ev.buf then M.active_buf = nil end
  end
end

function M.attach()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("TermRequest", {
    group = group,
    callback = on_term_request,
  })
  for _, evt in ipairs(Config.current.reset_on) do
    vim.api.nvim_create_autocmd(evt, {
      group = group,
      callback = on_reset,
    })
  end
end

function M.detach()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
end

return M
