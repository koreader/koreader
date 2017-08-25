--[[--
A TextWidget that handles long text wrapping

Example:

    local Foo = TextBoxWidget:new{
        face = Font:getFace("cfont", 25),
        text = 'We can show multiple lines.\nFoo.\nBar.',
        -- width = Screen:getWidth()*2/3,
    }
    UIManager:show(Foo)

]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local TimeVal = require("ui/timeval")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local util = require("util")

local TextBoxWidget = Widget:new{
    text = nil,
    charlist = nil,
    charpos = nil,
    char_width_list = nil, -- list of widths of the chars in `charlist`.
    vertical_string_list = nil,
    editable = false, -- Editable flag for whether drawing the cursor or not.
    justified = false, -- Should text be justified (spaces widened to fill width)
    cursor_line = nil, -- LineWidget to draw the vertical cursor.
    face = nil,
    bold = nil,
    line_height = 0.3, -- in em
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = 400, -- in pixels
    height = nil, -- nil value indicates unscrollable text widget
    virtual_line_num = 1, -- used by scroll bar
    _bb = nil,
}

function TextBoxWidget:init()
    self.line_height_px = (1 + self.line_height) * self.face.size
    self.cursor_line = LineWidget:new{
        dimen = Geom:new{
            w = Screen:scaleBySize(1),
            h = self.line_height_px,
        }
    }
    self:_evalCharWidthList()
    self:_splitCharWidthList()
    if self.height == nil then
        self:_renderText(1, #self.vertical_string_list)
    else
        self:_renderText(1, self:getVisLineCount())
    end
    if self.editable then
        local x, y
        x, y = self:_findCharPos()
        self.cursor_line:paintTo(self._bb, x, y)
    end
    self.dimen = Geom:new(self:getSize())
end

function TextBoxWidget:unfocus()
    self.editable = false
    self:init()
end

function TextBoxWidget:focus()
    self.editable = true
    self:init()
end

-- Split `self.text` into `self.charlist` and evaluate the width of each char in it.
function TextBoxWidget:_evalCharWidthList()
    if self.charlist == nil then
        self.charlist = util.splitToChars(self.text)
        self.charpos = #self.charlist + 1
    end
    self.char_width_list = {}
    -- use a cache to avoid many calls to RenderText:sizeUtf8Text()
    local char_width_cache = {}
    for _, v in ipairs(self.charlist) do
        local w = char_width_cache[v]
        if w == nil then
            w = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, v, true, self.bold).x
            char_width_cache[v] = w
        end
        table.insert(self.char_width_list, {char = v, width = w, pad = 0})
        -- pad will be updated if we do text justification
    end
end

-- Split the text into logical lines to fit into the text box.
function TextBoxWidget:_splitCharWidthList()
    self.vertical_string_list = {}

    local idx = 1
    local size = #self.char_width_list
    local ln = 1
    local offset, cur_line_width, cur_line_text
    while idx <= size do
        offset = idx
        -- Appending chars until the accumulated width exceeds `self.width`,
        -- or a newline occurs, or no more chars to consume.
        cur_line_width = 0
        local hard_newline = false
        local char_pads = nil
        while idx <= size do
            if self.char_width_list[idx].char == "\n" then
                hard_newline = true
                break
            end
            cur_line_width = cur_line_width + self.char_width_list[idx].width
            if cur_line_width > self.width then break else idx = idx + 1 end
        end
        if cur_line_width <= self.width then -- a hard newline or end of string
            cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
        else
            -- Backtrack the string until the length fit into one line.
            -- We'll give next and prev chars to isSplittable() for a wiser decision
            local c = self.char_width_list[idx].char
            local next_c = idx+1 <= size and self.char_width_list[idx+1].char or false
            local prev_c = idx-1 >= 1 and self.char_width_list[idx-1].char or false
            local adjusted_idx = idx
            local adjusted_width = cur_line_width
            while adjusted_idx > offset and not util.isSplittable(c, next_c, prev_c) do
                adjusted_width = adjusted_width - self.char_width_list[adjusted_idx].width
                adjusted_idx = adjusted_idx - 1
                next_c = c
                c = prev_c
                prev_c = adjusted_idx-1 >= 1 and self.char_width_list[adjusted_idx-1].char or false
            end
            if adjusted_idx == offset or adjusted_idx == idx then
                -- either a very long english word ocuppying more than one line,
                -- or the excessive char is itself splittable:
                -- we let that excessive char for next line
                if adjusted_idx == offset then -- let the fact a long word was splitted be known
                    self.has_split_inside_word = true
                end
                cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
                cur_line_width = cur_line_width - self.char_width_list[idx].width
            elseif c == " " then
                -- we backtracked and we're below max width, but the last char
                -- is a space, we can ignore it
                cur_line_text = table.concat(self.charlist, "", offset, adjusted_idx - 1)
                cur_line_width = adjusted_width - self.char_width_list[adjusted_idx].width
                idx = adjusted_idx + 1
            else
                -- we backtracked and we're below max width, we can leave the
                -- splittable char on this line
                cur_line_text = table.concat(self.charlist, "", offset, adjusted_idx)
                cur_line_width = adjusted_width
                idx = adjusted_idx + 1
            end
            if self.justified then
                -- this line was splitted and can be justified
                -- we build a list of char_pads, pixels to add to some chars to make the
                -- whole line justified
                local fill_width = self.width - cur_line_width
                if fill_width > 0 then
                    local _, nbspaces = string.gsub(cur_line_text, " ", "")
                    if nbspaces > 0 then
                        -- width added to all spaces
                        local space_add_w = math.floor(fill_width / nbspaces)
                        -- nb of spaces to which we'll add 1 more pixel
                        local space_add1_nb = fill_width - space_add_w * nbspaces
                        char_pads = {}
                        for cidx = offset, idx-1 do
                            local pad = 0
                            if self.char_width_list[cidx].char == " " then
                                pad = space_add_w
                                if space_add1_nb > 0 then
                                    pad = pad + 1
                                    space_add1_nb = space_add1_nb - 1
                                end
                                -- Update pad info, help for hold position accuracy
                                self.char_width_list[cidx].pad = pad
                            end
                            table.insert(char_pads, pad)
                        end
                    else
                        -- very long word, or CJK text with no space
                        -- pad first chars with 1 pixel
                        char_pads = {}
                        for cidx = offset, idx-1 do
                            local pad = 0
                            if fill_width > 0 then
                                pad = 1
                                fill_width = fill_width - 1
                                -- Update pad info, help for hold position accuracy
                                self.char_width_list[cidx].pad = pad
                            end
                            table.insert(char_pads, pad)
                        end
                    end
                end
            end
        end -- endif cur_line_width > self.width
        if cur_line_width < 0 then break end
        self.vertical_string_list[ln] = {
            text = cur_line_text,
            offset = offset,
            width = cur_line_width,
            char_pads = char_pads,
        }
        if hard_newline then
            idx = idx + 1
            -- FIXME: reuse newline entry
            self.vertical_string_list[ln+1] = {text = "", offset = idx, width = 0}
        else
            -- If next char is a space, discard it so it does not become
            -- an ugly leading space on the next line
            if idx <= size and self.char_width_list[idx].char == " " then
                idx = idx + 1
            end
        end
        ln = ln + 1
        -- Make sure `idx` point to the next char to be processed in the next loop.
    end
end

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    local font_height = self.face.size
    if start_row_idx < 1 then start_row_idx = 1 end
    if end_row_idx > #self.vertical_string_list then end_row_idx = #self.vertical_string_list end
    local row_count = end_row_idx == 0 and 1 or end_row_idx - start_row_idx + 1
    local h = self.line_height_px * row_count
    if self._bb then self._bb:free() end
    self._bb = Blitbuffer.new(self.width, h)
    self._bb:fill(Blitbuffer.COLOR_WHITE)
    local y = font_height
    for i = start_row_idx, end_row_idx do
        local line = self.vertical_string_list[i]
        local pen_x = self.alignment == "center" and (self.width - line.width)/2 or 0
            --@TODO Don't use kerning for monospaced fonts.    (houqp)
            -- refert to cb25029dddc42693cc7aaefbe47e9bd3b7e1a750 in master tree
        RenderText:renderUtf8Text(self._bb, pen_x, y, self.face, line.text, true, self.bold, self.fgcolor, nil, line.char_pads)
        y = y + self.line_height_px
    end
--    -- if text is shorter than one line, shrink to text's width
--    if #v_list == 1 then
--        self.width = pen_x
--    end
end

-- Return the position of the cursor corresponding to `self.charpos`,
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:_findCharPos()
    if self.text == nil or string.len(self.text) == 0 then
        return 0, 0
    end
    -- Find the line number.
    local ln = self.height == nil and 1 or self.virtual_line_num
    while ln + 1 <= #self.vertical_string_list do
        if self.vertical_string_list[ln + 1].offset > self.charpos then
            break
        else
            ln = ln + 1
        end
    end
    -- Find the offset at the current line.
    local x = 0
    local offset = self.vertical_string_list[ln].offset
    while offset < self.charpos do
        x = x + self.char_width_list[offset].width + self.char_width_list[offset].pad
        offset = offset + 1
    end
    return x + 1, (ln - 1) * self.line_height_px -- offset `x` by 1 to avoid overlap
end

function TextBoxWidget:moveCursorToCharpos(charpos)
    self.charpos = charpos
    local x, y = self:_findCharPos()
    self.cursor_line:paintTo(self._bb, x, y)
end

-- Click event: Move the cursor to a new location with (x, y), in pixels.
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:moveCursor(x, y)
    if #self.vertical_string_list == 0 then
        -- if there's no text at all, nothing to do
        return 1
    end
    local w = 0
    local ln = self.height == nil and 1 or self.virtual_line_num
    ln = ln + math.ceil(y / self.line_height_px) - 1
    if ln > #self.vertical_string_list then
        ln = #self.vertical_string_list
        x = self.width
    end
    local offset = self.vertical_string_list[ln].offset
    local idx = ln == #self.vertical_string_list and #self.char_width_list or self.vertical_string_list[ln + 1].offset - 1
    while offset <= idx do
        w = w + self.char_width_list[offset].width + self.char_width_list[offset].pad
        if w > x then break else offset = offset + 1 end
    end
    if w > x then
        local w_prev = w - self.char_width_list[offset].width - self.char_width_list[offset].pad
        if x - w_prev < w - x then -- the previous one is more closer
            w = w_prev
        else
            offset = offset + 1
        end
    end
    self:free()
    self:_renderText(1, #self.vertical_string_list)
    self.cursor_line:paintTo(self._bb, w + 1,
                             (ln - self.virtual_line_num) * self.line_height_px)
    return offset
end

function TextBoxWidget:getVisLineCount()
    return math.floor(self.height / self.line_height_px)
end

function TextBoxWidget:getAllLineCount()
    return #self.vertical_string_list
end


-- TODO: modify `charpos` so that it can render the cursor
function TextBoxWidget:scrollDown()
    local visible_line_count = self:getVisLineCount()
    if self.virtual_line_num + visible_line_count <= #self.vertical_string_list then
        self:free()
        self.virtual_line_num = self.virtual_line_num + visible_line_count
        self:_renderText(self.virtual_line_num, self.virtual_line_num + visible_line_count - 1)
    end
    return (self.virtual_line_num - 1) / #self.vertical_string_list, (self.virtual_line_num - 1 + visible_line_count) / #self.vertical_string_list
end

-- TODO: modify `charpos` so that it can render the cursor
function TextBoxWidget:scrollUp()
    local visible_line_count = self:getVisLineCount()
    if self.virtual_line_num > 1 then
        self:free()
        if self.virtual_line_num <= visible_line_count then
            self.virtual_line_num = 1
        else
            self.virtual_line_num = self.virtual_line_num - visible_line_count
        end
        self:_renderText(self.virtual_line_num, self.virtual_line_num + visible_line_count - 1)
    end
    return (self.virtual_line_num - 1) / #self.vertical_string_list, (self.virtual_line_num - 1 + visible_line_count) / #self.vertical_string_list
end

function TextBoxWidget:getSize()
    if self.width and self.height then
        return Geom:new{ w = self.width, h = self.height}
    else
        return Geom:new{ w = self.width, h = self._bb:getHeight()}
    end
end

function TextBoxWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:blitFrom(self._bb, x, y, 0, 0, self.width, self._bb:getHeight())
end

function TextBoxWidget:free()
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

-- Allow selection of a single word at hold position
function TextBoxWidget:onHoldWord(callback, ges)
    if not callback then return end

    local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    local line_num = math.ceil(y / self.line_height_px) + self.virtual_line_num-1
    local line = self.vertical_string_list[line_num]
    logger.dbg("holding on line", line)
    if line then
        local char_start = line.offset
        local char_end  -- char_end is non-inclusive
        if line_num >= #self.vertical_string_list then
            char_end = #self.char_width_list + 1
        else
            char_end = self.vertical_string_list[line_num+1].offset
        end
        local char_probe_x = 0
        local idx = char_start
        -- find which character the touch is holding
        while idx < char_end do
            local c = self.char_width_list[idx]
            -- FIXME: this might break if kerning is enabled
            char_probe_x = char_probe_x + c.width + c.pad
            if char_probe_x > x then
                -- ignore spaces
                if c.char == " " then break end
                -- now find which word the character is in
                local words = util.splitToWords(line.text)
                local probe_idx = char_start
                for _, w in ipairs(words) do
                    -- +1 for word separtor
                    probe_idx = probe_idx + #util.splitToChars(w)
                    if idx <= probe_idx - 1 then
                        callback(w)
                        return
                    end
                end
                break
            end
            idx = idx + 1
        end
    end

    return
end


-- Allow selection of one or more words (with no visual feedback)
-- Gestures should be declared in widget using us (e.g dictquicklookup.lua)

-- Constants for which side of a word to find
local FIND_START = 1
local FIND_END = 2

function TextBoxWidget:onHoldStartText(_, ges)
    -- just store hold start position and timestamp, will be used on release
    self.hold_start_x = ges.pos.x - self.dimen.x
    self.hold_start_y = ges.pos.y - self.dimen.y
    self.hold_start_tv = TimeVal.now()
    return true
end

function TextBoxWidget:onHoldReleaseText(callback, ges)
    if not callback then return end

    local hold_end_x = ges.pos.x - self.dimen.x
    local hold_end_y = ges.pos.y - self.dimen.y

    -- check we have seen a HoldStart event
    if not self.hold_start_tv then
        return false
    end
    -- check start and end coordinates are actually inside our area
    if self.hold_start_x < 0 or hold_end_x < 0 or
        self.hold_start_x > self.dimen.w or hold_end_x > self.dimen.w or
        self.hold_start_y < 0 or hold_end_y < 0 or
        self.hold_start_y > self.dimen.h or hold_end_y > self.dimen.h then
        return false
    end

    local hold_duration = TimeVal.now() - self.hold_start_tv
    hold_duration = hold_duration.sec + hold_duration.usec/1000000

    -- Swap start and end if needed
    local x0, y0, x1, y1
    -- first, sort by y/line_num
    local start_line_num = math.ceil(self.hold_start_y / self.line_height_px)
    local end_line_num = math.ceil(hold_end_y / self.line_height_px)
    if start_line_num < end_line_num then
        x0, y0 = self.hold_start_x, self.hold_start_y
        x1, y1 = hold_end_x, hold_end_y
    elseif start_line_num > end_line_num then
        x0, y0 = hold_end_x, hold_end_y
        x1, y1 = self.hold_start_x, self.hold_start_y
    else -- same line_num : sort by x
        if self.hold_start_x <= hold_end_x then
            x0, y0 = self.hold_start_x, self.hold_start_y
            x1, y1 = hold_end_x, hold_end_y
        else
            x0, y0 = hold_end_x, hold_end_y
            x1, y1 = self.hold_start_x, self.hold_start_y
        end
    end

    -- Reset start infos, so we do not reuse them and can catch
    -- a missed start event
    self.hold_start_x = nil
    self.hold_start_y = nil
    self.hold_start_tv = nil

    -- similar code to find start or end is in _findWordEdge() helper
    local sel_start_idx = self:_findWordEdge(x0, y0, FIND_START)
    local sel_end_idx = self:_findWordEdge(x1, y1, FIND_END)

    if not sel_start_idx or not sel_end_idx then
        -- one or both hold points were out of text
        return true
    end

    local selected_text = table.concat(self.charlist, "", sel_start_idx, sel_end_idx)
    logger.dbg("onHoldReleaseText (duration:", hold_duration, ") :", sel_start_idx, ">", sel_end_idx, "=", selected_text)
    callback(selected_text, hold_duration)
    return true
end

function TextBoxWidget:_findWordEdge(x, y, side)
    if side ~= FIND_START and side ~= FIND_END then
        return
    end
    local line_num = math.ceil(y / self.line_height_px) + self.virtual_line_num-1
    local line = self.vertical_string_list[line_num]
    if not line then
        return -- below last line : no selection
    end
    local char_start = line.offset
    local char_end  -- char_end is non-inclusive
    if line_num >= #self.vertical_string_list then
        char_end = #self.char_width_list + 1
    else
        char_end = self.vertical_string_list[line_num+1].offset
    end
    local char_probe_x = 0
    local idx = char_start
    local edge_idx = nil
    -- find which character the touch is holding
    while idx < char_end do
        local c = self.char_width_list[idx]
        char_probe_x = char_probe_x + c.width + c.pad
        if char_probe_x > x then
            -- character found, find which word the character is in, and
            -- get its start/end idx
            local words = util.splitToWords(line.text)
            -- words may contain separators (space, punctuation) : we don't
            -- discriminate here, it's the caller job to clean what was
            -- selected
            local probe_idx = char_start
            local next_probe_idx
            for _, w in ipairs(words) do
                next_probe_idx = probe_idx + #util.splitToChars(w)
                if idx < next_probe_idx then
                    if side == FIND_START then
                        edge_idx = probe_idx
                    elseif side == FIND_END then
                        edge_idx = next_probe_idx - 1
                    end
                    break
                end
                probe_idx = next_probe_idx
            end
            if edge_idx then
                break
            end
        end
        idx = idx + 1
    end
    return edge_idx
end

return TextBoxWidget
