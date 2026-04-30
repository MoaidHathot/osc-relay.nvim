local M = {}

---@class OscRelay.Config
---@field enabled boolean
---@field allow string[]               OSC selectors to relay; "*" = all
---@field deny string[]                OSC selectors to never relay
---@field scope "focused"|"all"|fun(buf: integer): boolean
---@field multiplex "auto"|"tmux"|"zellij"|"off"
---@field reset_on string[]            autocmd events that clear the bar
---@field notify boolean               fire User OscRelay autocmd alongside sink
---@field debug boolean

---@type OscRelay.Config
M.defaults = {
  enabled = true,
  allow = { "9;4" },
  deny = {},
  scope = "focused",
  multiplex = "auto",
  reset_on = { "TermClose", "VimLeavePre" },
  notify = true,
  debug = false,
}

---@type OscRelay.Config
M.current = vim.deepcopy(M.defaults)

---@param opts? table
function M.merge(opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.current
end

return M
