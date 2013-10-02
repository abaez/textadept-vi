local M = {}

local state = {
    tags = nil,   -- current set of tags
    tagstack = {},-- current tag stack: list of { i=num, tags={tag list} }
    tagidx = 0,   -- index into tagstack of current level
    lasttag = nil,-- last tag list
}
M.state = state

-- Load a tags file
local function load_tags()
    local tagf = io.open("tags") -- TODO: configurable tags file location
    local results = {}
    local pat = "^([^\t]*)\t([^\t]*)\t(.*)$"
    if tagf then
      for line in tagf:lines() do
          local tname, fname, excmd = line:match(pat)
          local flags
          if tname then
            -- Initialise to an empty list if necessary
            if not results[tname] then results[tname] = {} end
            -- And append.
            local l = results[tname]  -- now guaranteed to be a table
          
            do
               -- Try to separate the ex command from extension fields
               local e,f = excmd:match('^(.-);"\t(.*)$')
               if e then
                   excmd = e
                   flags = f
               end
            end
            l[#l+1] = { sym=tname, filename=fname, excmd=excmd, flags=flags }
          end
      end
      tagf:close()
    end
    state.tags = results
end

-- Return or load the tags
local function get_tags()
    -- TODO: check if tags file needs reloading
    if state.tags == nil then
        load_tags()
    end
    return state.tags
end

function M.find_tag_exact(name)
    local tags = get_tags()
    local result = tags[name]
    if result then
        local newidx = state.tagidx + 1
        
        -- Clear the stack above where we are.
        while newidx <= #state.tagstack do
            state.tagstack[#state.tagstack] = nil
        end
        
        state.tagstack[newidx] = {
           i=1,         -- which tag within this list
           tags=result, -- this level's tags
           fromname=buffer.filename,  -- where we came from
           frompos=buffer.current_pos,-- where we came from
        }
        state.lasttag = result
        state.tagidx = newidx
        return result[1]
    else
        return nil
    end
end

-- Return a list of tags matching Lua pat
function M.match_tag(pat)
    local tags = get_tags()
    local result = {}
    for name,_ in pairs(tags) do
        if name:match(pat) then
            result[#result+1] = name
        end
    end
    if #result > 0 then return result end
    -- return nil if nothing found
end

function M.pop_tag()
    if state.tagidx >= 1 then
        local tos = state.tagstack[state.tagidx]
        io.open_file(tos.fromname)
        buffer.goto_pos(tos.frompos)
        state.tagidx = state.tagidx - 1
    else
        vi_mode.err("Top of stack")
    end
end

-- Return all the tags in the current level
function M.get_all()
    if state.tagidx > 0 then
        return state.tagstack[state.tagidx].tags
    end
end

-- Go to a particular tag
function M.goto_tag(tag)
    io.open_file(tag.filename)
    local excmd = tag.excmd
    
    local _, pat = excmd:match("^([?/])(.*)%1$")
    if pat then
        -- TODO: properly handle regexes and line number tags.
        -- For now, assume it's a fixed string possibly with ^ and $ around it.
        pat = pat:match("^^?(.-)$?$")
        buffer.current_pos = 0
        buffer.search_anchor()
        local pos = buffer.search_next(0, pat)
        if pos >= 0 then
            buffer.goto_pos(pos)
        else
            gui.statusbar_text = "Not found: " .. pat
        end
        return
    end
    
    -- Try a numeric line number
    local pat = excmd:match("^(%d+)$")
    if pat then
        buffer.goto_line(tonumber(pat)-1)
        return
    end
    
    -- unknown tag pattern
    vi_mode.err('Tag pat: '..excmd)
end

-- Return the next tag at this level, or nil.
function M.tag_next()
    local taglist = state.tagstack[state.tagidx]
    if taglist.i < #taglist.tags then
        taglist.i = taglist.i + 1
        return taglist.tags[taglist.i]
    end
end

-- Return the next tag at this level, or nil.
function M.tag_prev()
    local taglist = state.tagstack[state.tagidx]
    if taglist.i > 1 then
        taglist.i = taglist.i - 1
        return taglist.tags[taglist.i]
    end
end

return M
