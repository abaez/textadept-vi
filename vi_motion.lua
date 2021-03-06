-- Support for motion key sequences
local M = {}

-- Implementations of the movements
local vi_motions = require 'vi_motions'

-- Wrap a possibly nested table, returning a proxy which modifies any value
-- which isn't a nested table.  A nested table is considered one with no
-- integer keys (so #t == 0, or t[1] == nil).  This allows storing values
-- such as { 1,2,3 }.
-- Parameters:
--   tab: the table to wrap
--   f:   function to modify the value from tab.
local function wrap_table(tab, f)
    result = setmetatable({wrapped=1, tt=tab}, {
        __index = function(t, k)
            local m = tab[k]
            
            if m == nil then
                return nil
            elseif type(m) == 'table' and m[1] == nil then
                return wrap_table(m, f)
            else
                -- Return a (possibly modified) value.
                return f(m)
            end
        end,
    })
    return result
end

M.wrap_table = wrap_table

-- Valid movement types
MOV_LINE = 'linewise'
MOV_INC = 'inclusive'
MOV_EXC = 'exclusive'

-- Postponed movement.  The movement isn't complete (eg a search needs entering), and should
-- be called with a continuation function, which will be called back later with the actual
-- movement.
MOV_LATER = 'later'

-- Wrap a simple movement (eg word right) into one which takes a repeat
-- count.
local function r(f)
    return function(rep)
      if rep==nil or rep < 1 then
          rep = 1
      end
      for i=1,rep do
          f()
      end
    end
end
M.r = r

-- Table of register keys, returning true.
local registers = setmetatable({splogde=123}, {
  __index = function(t, key)
    if string.match(key, "^%a$") then
      return key
    else
      return nil
    end
  end,
})

local function restore_mark(reg)

    return { MOV_LINE, function()
        newpos = vi_mode.state.marks[reg]
        newpos = buffer:position_from_line(buffer:line_from_position(newpos))
        if newpos ~= nil then
            buffer:goto_pos(newpos)
        end
     end, 1 }
end

-- Table of basic motion commands.  Each is a list:
-- { type, f, count }
-- where f is a function to do the movement, type is one of
-- MOV_LINE, MOV_EXC, MOV_INC for linewise, exclusive or inclusive,
-- and count is the prefix count.  This may be modified when wrapped.
local motions = {
  h = { MOV_EXC, r(vi_motions.char_left), 1 },
  l = { MOV_EXC, r(vi_motions.char_right), 1 },
  j = { MOV_LINE, r(vi_motions.line_down), 1 },
  k = { MOV_LINE, r(vi_motions.line_up), 1 },
  w = { MOV_EXC, r(vi_motions.word_right), 1 },
  b = { MOV_EXC, r(vi_motions.word_left), 1 },
  e = { MOV_INC, r(vi_motions.word_end), 1 },
  ['$'] = { MOV_INC, vi_motions.line_end, 1 },
  ['^'] = { MOV_EXC, vi_motions.line_beg, 1 },
  G = { MOV_LINE, vi_motions.goto_line, -1},
  ["'"] = wrap_table(registers, restore_mark),
  ['%'] = { MOV_INC, vi_motions.match_brace, 1 },
  
  -- Search motions
  n = { MOV_EXC, r(vi_motions.search_next), 1 },
  N = { MOV_EXC, r(vi_motions.search_prev), 1 },
  ['*'] = { MOV_EXC, r(vi_motions.search_word_next), 1 },
  ['#'] = { MOV_EXC, r(vi_motions.search_word_prev), 1 },
  ['/'] = { MOV_LATER, vi_motions.search_fwd, 1 },
  ['?'] = { MOV_LATER, vi_motions.search_back, 1 },
}
local MOTION_ZERO = { MOV_EXC, vi_motions.line_start, 1 }
local digits = {}
for i=0,9 do
    digits[i..''] = true
end
local PREFIX_COUNT = 'laksdjfasdlf' --{} -- unique table key
local function index_digits(t, k)
    -- Intercept numbers to return an wrapped version.
    if digits[k] then
        local precount = t[PREFIX_COUNT]
        if precount == nil and k == '0' then
            return MOTION_ZERO -- special case - 0 is a motion by itself.
        end
        
        -- Rely on the master table never having PREFIX_COUNT.
        if precount == nil then
            local wrapped = t
            -- If this is the first digit, return a wrapped table
            local newtab = setmetatable({}, {
                --__index=wrapped,
                __index = function(wt, k)
                    -- We already have a prefix count, so increment it.
                    if digits[k] then
                        wt[PREFIX_COUNT] = wt[PREFIX_COUNT] * 10 + (k+0)
                        return t
                    else
                        local res = wrapped[k]
                        
                        if type(res)=='table' and res[1] then
                            -- This is a motion, so apply the multiple
                            res = { res[1], res[2], wt[PREFIX_COUNT] }
                        end
                        return res
                    end
                end})
            t = newtab
            precount = 0
        end
            
        -- Update the count in the (possibly new) wrapper table
        precount = (precount * 10) + (k+0)
        t[PREFIX_COUNT] = precount
        
        -- Return the wrapper
        return t
    else
        -- not found
        return nil
    end
end

setmetatable(motions, {
  __index = index_digits,
})
M.motions = motions

-- Convert a simple movement desc into a selection movdesc
function M.movf_to_self(movedesc)
    local movtype, mov_f, rep = table.unpack(movedesc)
    -- Convert simple movement into a range
    return { movtype, function(rep)
        local pos1 = buffer.current_pos
        mov_f(rep)
        local pos2 = buffer.current_pos
        if pos1 > pos2 then
            pos1, pos2 = pos2, pos1
        end
        return pos1, pos2
      end, rep }
end

-- Table of select (range) motions, used after some commands (eg d{motion}).
-- Each entry is a function returning (start, end) positions.
local sel_motions = setmetatable({
  a = {
      w = { MOV_EXC, function()
             local pos = buffer.current_pos
             local s = buffer:word_start_position(pos, true)
             buffer:search_anchor()
             local e = buffer:search_next(buffer.FIND_REGEXP, "\\s\\w") + 1
             
             return s, e
          end, 1},
--    W = function() return 'WORD' end,
  },
  i = {
      w = { MOV_EXC, function()
             local pos = buffer.current_pos
             local s = buffer:word_start_position(pos, true)
             local e = buffer:word_end_position(pos)
             
             return s, e
          end, 1},
--    W = function() return 'WORD' end,
  },
}, {
  __index=wrap_table(motions, M.movf_to_self),
})
  
M.sel_motions = sel_motions

-- Return an entry suitable for the keys table which implements the vi motion
-- commands.
-- actions: a table of overrides (subcommands which aren't motions), eg for
-- a 'd' handler, this would include 'd' (for 'dd', which deletes the current
-- line).
-- handler: Is called with a movdesc, and should return a no-parameter
-- function which will implement the action.
function M.bind_motions(actions, handler)
    local keyseq = {}
    setmetatable(actions, { __index=sel_motions })
    return wrap_table(actions, handler)
end

return M