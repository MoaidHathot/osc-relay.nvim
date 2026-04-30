-- OSC sequence parser + allow/deny matching.
-- An OSC sequence has the shape: ESC ] <selector> ; <payload> ST
-- where <selector> is digits, optionally "<digits>;<digits>" (e.g. "9;4").
-- ST is either ESC \ or BEL (0x07).
local M = {}

---Parse the OSC selector out of a raw sequence (with or without ESC] prefix).
---@param seq string
---@return string? selector  e.g. "0", "9;4"; nil if not an OSC
---@return string? payload   text after the selector's first `;`, sans terminator
function M.parse(seq)
  if not seq or seq == "" then return nil end
  -- strip ESC ] prefix if present
  local s = seq:gsub("^\27%]", "")
  -- strip terminator
  s = s:gsub("\27\\$", ""):gsub("\7$", "")
  -- match leading "<digits>" or "<digits>;<digits>"
  local sel, rest = s:match("^(%d+;%d+)(.*)$")
  if not sel then sel, rest = s:match("^(%d+)(.*)$") end
  if not sel then return nil end
  local payload = rest:match("^;(.*)$") or ""
  return sel, payload
end

---@param sel string
---@param list string[]
---@return boolean
local function matches(sel, list)
  for _, p in ipairs(list) do
    if p == "*" or p == sel then return true end
  end
  return false
end

---@param seq string
---@param allow string[]
---@param deny string[]
---@return boolean pass, string? selector
function M.check(seq, allow, deny)
  local sel = M.parse(seq)
  if not sel then return false, nil end
  if matches(sel, deny) then return false, sel end
  if not matches(sel, allow) then return false, sel end
  return true, sel
end

return M
