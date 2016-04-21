local Blitbuffer = require("ffi/blitbuffer")
local Widget = require("ui/widget/widget")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local util = require("util")
local DEBUG = require("dbg")

--[[
A TextWidget that handles long text wrapping
--]]
local TextBoxWidget = Widget:new{
    text = nil,
	charlist = nil,
	charpos = nil,
	char_width_list = nil, -- list of widths of the chars in `charlist`.
    vertical_string_list = nil,
	editable = false, -- Editable flag for whether drawing the cursor or not.
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
	print("XXXXXXXXXXXXXXXXXXXX TextBoxWidget:init() ", self.height)
	local line_height = (1 + self.line_height) * self.face.size
	local font_height = self.face.size
	self.cursor_line = LineWidget:new{
        dimen = Geom:new{
            w = Screen:scaleBySize(1),
            h = line_height,
        }
    }
	print("########################### Rendering text", self.text)
	print("########################### charlist", self.charlist)
	self:_evalCharWidthList()
	print("########################### char_width_list", self.char_width_list)
	for k, v in ipairs(self.char_width_list) do
		print("############################", k, v.char, v.width)
	end
	self:_splitCharWidthList()
	print("######################### Text Widget vetical_string_list", self.vertical_string_list)
	for k, v in ipairs(self.vertical_string_list) do
		print("############################", k, v.text, v.offset)
	end
	if self.height == nil then
		self:_renderText(1, #self.vertical_string_list)
	else
		print("$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$ scorlling widget", self:getVisLineCount())
		self:_renderText(1, self:getVisLineCount())
	end
	if self.editable then
		x, y = self:_findCharPos()
		print("####################### Drawing cursor at ", x, y, self.charpos)
		self.cursor_line:paintTo(self._bb, x, y)
	end
	self.dimen = Geom:new(self:getSize())
end

-- Return whether the text widget is editable.
function TextBoxWidget:isEditable()
	return self.editable
end

-- Evaluate the width of each char in `self.charlist`.
function TextBoxWidget:_evalCharWidthList()
	if self.charlist == nil then
		self.charlist = {}
		util.splitToChars(self.text, self.charlist)
		self.charpos = #self.charlist + 1
	end
	self.char_width_list = {}
	for _, v in ipairs(self.charlist) do
		w = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, v, true, self.bold).x
		table.insert(self.char_width_list, {char = v, width = w})
	end
end

-- Split the text into logical lines to fit into the text box.
function TextBoxWidget:_splitCharWidthList()
	self.vertical_string_list = {}
	self.vertical_string_list[1] = {text = "Demo hint", offset = 1, width = 0} -- hint for empty string

	local idx = 1
	local offset = 1
    local cur_line_width = 0
	local cur_line_text = nil
	local size = #self.char_width_list
	local ln = 1
	while idx <= size do
		offset = idx
		-- Appending chars until the accumulated width exceeds `self.width`,
		-- or a newline occurs, or no more chars to consume.
		cur_line_width = 0
		local hard_newline = false
		cur_line_text = nil
		while idx <= size do
			if self.char_width_list[idx].char == "\n" then
				hard_newline = true
				break
			end
			cur_line_width = cur_line_width + self.char_width_list[idx].width
			print("++++++++", cur_line_width, idx, self.char_width_list[idx].width, self.char_width_list[idx].char)
			if cur_line_width > self.width then break else idx = idx + 1 end
		end
		print("xxxxxxx Beofre ", cur_line_width, offset, idx, "++++++++++ self.width", self.width)
		if cur_line_width <= self.width then -- a hard newline or end of string
			cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
			print("XXX nature end", cur_line_text, "?????", #self.charlist)
		else
			-- Backtrack the string until the length fit into one line.
			print("XXX overbounded")
			local c = self.char_width_list[idx].char
			if util.isSplitable(c) then
				cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
				cur_line_width = cur_line_width - self.char_width_list[idx].width
			else
				local adjusted_idx = idx
				local adjusted_width = cur_line_width
				repeat
					print("<----", self.char_width_list[adjusted_idx])
					adjusted_width = adjusted_width - self.char_width_list[adjusted_idx].width
					adjusted_idx = adjusted_idx - 1
					c = self.char_width_list[adjusted_idx].char
				until adjusted_idx > offset and util.isSplitable(c)
				if adjusted_idx == offset then -- a very long english word ocuppying more than one line
					cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
					cur_line_width = cur_line_width - self.char_width_list[idx].width
					print("!!!!! A very long word cut to ", cur_line_text)
				else
					cur_line_text = table.concat(self.charlist, "", offset, adjusted_idx)
					cur_line_width = adjusted_line_width
					print("now the text is ", cur_line_text, "(", adjusted_line_width, ")", offset, adjusted_idx)
					idx = adjusted_idx + 1
				end
			end -- endif util.isSplitable(c)
		end -- endif cur_line_width > self.width
		self.vertical_string_list[ln] = {text = cur_line_text, offset = offset, width = cur_line_width}
		if hard_newline then
			idx = idx + 1
			self.vertical_string_list[ln + 1] = {text = "", offset = idx, width = 0}
		end
		ln = ln + 1
		-- Make sure `idx` point to the next char to be processed in the next loop.
	end
end

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
	print("@@@@@@@@@@@@@@@@@@@", start_row_idx, end_row_idx)
    local font_height = self.face.size
    local line_height = (1 + self.line_height) * font_height
	if start_row_idx < 1 then start_row_idx = 1 end
	if end_row_idx > #self.vertical_string_list then end_row_idx = #self.vertical_string_list end
	local row_count = end_row_idx == 0 and 1 or end_row_idx - start_row_idx + 1
    local h = line_height *  row_count
    self._bb = Blitbuffer.new(self.width, h)
    self._bb:fill(Blitbuffer.COLOR_WHITE)
	print("XXXX rendering height", h, line_height, start_row_idx, end_row_idx)
	local y = font_height
	for i = start_row_idx, end_row_idx do
		print("printing row", i, self.vertical_string_list[i].text)
		local line = self.vertical_string_list[i]
		local pen_x = self.alignment == "center" and (self.width - line.width)/2 or 0
			--@TODO Don't use kerning for monospaced fonts.    (houqp)
			-- refert to cb25029dddc42693cc7aaefbe47e9bd3b7e1a750 in master tree
		RenderText:renderUtf8Text(self._bb, pen_x, y, self.face, line.text, true, self.bold, self.fgcolor)
		y = y + line_height
	end
--    -- if text is shorter than one line, shrink to text's width
--    if #v_list == 1 then
--        self.width = pen_x
--    end
end

-- Return the position of the cursor corresponding to `self.charpos`,
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:_findCharPos()
	print("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF findCharPos", self.charpos)
	-- Find the line number.
	local ln = self.height == nil and 1 or self.virtual_line_num
	while ln + 1 <= #self.vertical_string_list do
		if self.vertical_string_list[ln + 1].offset > self.charpos then break else ln = ln + 1 end
		print("XXXXXX", ln, self.vertical_string_list[ln].offset, self.charpos)
	end
	print("^^^^^^^^^^^^locating at real line", ln, "virutal line", ln - self.virtual_line_num + 1)
	-- Find the offset at the current line.
	local x = 0
	print("self.char_width_list", self.char_width_list)
	local offset = self.vertical_string_list[ln].offset
	while offset < self.charpos do
		print("+++", offset, self.charpos)
		x = x + self.char_width_list[offset].width
		offset = offset + 1
	end
	print("^^^^^^^^^^^locating at width ", x)
	local line_height = (1 + self.line_height) * self.face.size
	return x + 1, (ln - 1) * line_height -- offset `x` by 1 to avoid overlap
end

-- Click event: Move the cursor to a new location with (x, y), in pixels.
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:moveCursor(x, y)
	local w = 0
	local h = 0
	local line_height = (1 + self.line_height) * self.face.size
	local ln = self.height == nil and 1 or self.virtual_line_num
	ln = ln + math.ceil(y / line_height) - 1
	if ln > #self.vertical_string_list then
		print("&&&&&&&&&&&& Press some empty area....")
		ln = #self.vertical_string_list
		x = self.width
	end
	print("Real line number", ln, "virtual line number", ln - self.virtual_line_num + 1)
	local offset = self.vertical_string_list[ln].offset
	local idx = ln == #self.vertical_string_list and #self.char_width_list or self.vertical_string_list[ln + 1].offset - 1
	print("XXXX", offset, idx)
	while offset <= idx do
		w = w + self.char_width_list[offset].width
		print("XXXXX", offset, idx, w)
		if w > x then break else offset = offset + 1 end
	end
	print("XXXX After loop", offset, idx, w)
	if w > x then
		local w_prev = w - self.char_width_list[offset].width
		if x - w_prev < w - x then -- the previous one is more closer
			w = w_prev
		end
	end
	print("$$$$$$$$$$$$$$$$$$$$$$$$ adjusted", w)
	print("painting", w, ln - self.virtual_line_num + 1)
	self:free()
	self:_renderText(1, #self.vertical_string_list)
	self.cursor_line:paintTo(self._bb, w + 1, (ln - self.virtual_line_num) * line_height)
	return offset
end

function TextBoxWidget:getVisLineCount()
    local line_height = (1 + self.line_height) * self.face.size
    return math.floor(self.height / line_height)
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

function TextBoxWidget:onHoldWord(callback, ges)
    local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    for _, l in ipairs(self.rendering_vlist) do
        for _, w in ipairs(l) do
            local box = w.box
            if x > box.x and x < box.x + box.w and
                y > box.y and y < box.y + box.h then
                DEBUG("found word", w, "at", x, y)
                if callback then
                    callback(w.word)
                end
                break
            end
        end
    end
    return true
end

return TextBoxWidget
