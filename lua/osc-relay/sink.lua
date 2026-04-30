-- Writes raw bytes out of nvim's controlling terminal so the host (e.g.
-- Windows Terminal) sees them. Wraps in tmux DCS passthrough when nested.
local M = {}

local function detect_mux(setting)
  if setting == "off" then return nil end
  if setting == "tmux" then return "tmux" end
  if setting == "zellij" then return "zellij" end
  -- auto
  if vim.env.TMUX and vim.env.TMUX ~= "" then return "tmux" end
  if vim.env.ZELLIJ and vim.env.ZELLIJ ~= "" then return "zellij" end
  return nil
end

---@param bytes string
---@param mux "tmux"|"zellij"|nil
---@return string
local function wrap(bytes, mux)
  if mux == "tmux" then
    -- tmux DCS passthrough: ESC P tmux; <inner with ESC -> ESC ESC> ESC \
    local inner = bytes:gsub("\27", "\27\27")
    return "\27Ptmux;" .. inner .. "\27\\"
  end
  -- zellij has no general OSC passthrough; pass through unwrapped
  return bytes
end

---Write bytes to the host terminal. Best-effort; never throws.
---@param bytes string
---@param mux_setting string  "auto"|"tmux"|"zellij"|"off"
function M.write(bytes, mux_setting)
  local mux = detect_mux(mux_setting)
  local out = wrap(bytes, mux)
  local ok = pcall(function()
    vim.uv.fs_write(2, out)
  end)
  if not ok then
    pcall(function()
      io.stderr:write(out)
      io.stderr:flush()
    end)
  end
end

return M
