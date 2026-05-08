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
  if type(scope) == "function" then
    return scope(buf) == true
  end
  if scope == "all" then
    return true
  end
  if scope == "focused" then
    return vim.api.nvim_get_current_buf() == buf
  end
  return false
end

---@param buf integer
---@return boolean
local function buf_active(buf)
  if M.buf_enabled[buf] == false then
    return false
  end
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
  if not buf_active(buf) then
    return
  end
  if not in_scope(buf) then
    return
  end
  local data = ev.data or {}
  local raw = data.sequence
  if type(raw) ~= "string" or raw == "" then
    return
  end

  -- Defensive: a single TermRequest event may carry multiple OSCs
  -- back-to-back if the child wrote them in one stdout.write. Split and
  -- evaluate each independently so allow/deny works per-OSC.
  local parts = Filter.split(raw)
  if #parts == 0 then
    parts = { raw }
  end

  for _, seq in ipairs(parts) do
    local pass, sel = Filter.check(seq, Config.current.allow, Config.current.deny)
    if pass and sel then
      -- Normalize: ensure ESC] prefix and ST terminator.
      if not seq:find("\27\\$") and not seq:find("\7$") then
        seq = seq .. "\27\\"
      end
      if not seq:find("^\27%]") then
        seq = "\27]" .. seq
      end
      dispatch(seq, buf, sel)
    end
  end
end

local function on_reset(ev)
  -- Only reset if this buffer was the last forwarder, or on global exit.
  if ev.event == "VimLeavePre" or M.active_buf == ev.buf or M.active_buf == nil then
    Sink.write(OSC_RESET, Config.current.multiplex)
    M.last[ev.buf] = nil
    if M.active_buf == ev.buf then
      M.active_buf = nil
    end
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
