-- OSC sequence parser + allow/deny matching.
-- An OSC sequence has the shape: ESC ] <selector> ; <payload> ST
-- where <selector> is digits, optionally "<digits>;<digits>" (e.g. "9;4").
-- ST is either ESC \ or BEL (0x07).
local M = {}

---Parse the OSC selector out of a single raw sequence.
---@param seq string  one OSC, may include ESC] prefix and ST terminator
---@return string? selector  e.g. "0", "9;4"; nil if not an OSC
---@return string? payload   text after the selector's first `;`, sans terminator
function M.parse(seq)
  if not seq or seq == "" then return nil end
  local s = seq:gsub("^\27%]", "")
  s = s:gsub("\27\\$", ""):gsub("\7$", "")
  local sel, rest = s:match("^(%d+;%d+)(.*)$")
  if not sel then sel, rest = s:match("^(%d+)(.*)$") end
  if not sel then return nil end
  local payload = rest:match("^;(.*)$") or ""
  return sel, payload
end

---Split an input that may contain multiple back-to-back OSC sequences into
---a list of individual sequences (each with its terminator).
---Defensive against tools that emit several OSCs in one stdout.write.
---@param input string
---@return string[]
function M.split(input)
  if not input or input == "" then return {} end
  local out = {}
  local i = 1
  local len = #input
  while i <= len do
    local start = input:find("\27%]", i)
    if not start then break end
    -- find terminator: ESC \ (two bytes) or BEL (one byte)
    local term_st = input:find("\27\\", start + 2, true)
    local term_bel = input:find("\7", start + 2, true)
    local term_end
    if term_st and (not term_bel or term_st <= term_bel) then
      term_end = term_st + 1 -- inclusive of the backslash
    elseif term_bel then
      term_end = term_bel
    else
      -- no terminator found; take rest as-is
      table.insert(out, input:sub(start))
      break
    end
    table.insert(out, input:sub(start, term_end))
    i = term_end + 1
  end
  return out
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
