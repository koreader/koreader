require "ui/rendertext"
require "ui/widget/base"
require "ui/widget/scrollbar"

--[[
A TextWidget puts a string on a single line
--]]
TextWidget = Widget:new{
	text = nil,
	face = nil,
	bgcolor = 0.0, -- [0.0, 1.0]
	fgcolor = 1.0, -- [0.0, 1.0]
	_bb = nil,
	_length = 0,
	_height = 0,
	_maxlength = 1200,
}

--function TextWidget:_render()
	--local h = self.face.size * 1.3
	--self._bb = Blitbuffer.new(self._maxlength, h)
	--self._length = renderUtf8Text(self._bb, 0, h*0.8, self.face, self.text, self.color)
--end

function TextWidget:getSize()
	--if not self._bb then
		--self:_render()
	--end
	--return { w = self._length, h = self._bb:getHeight() }
	local tsize = sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true)
	if not tsize then
		return Geom:new{}
	end
	self._length = tsize.x
	self._height = self.face.size * 1.5
	return Geom:new{
		w = self._length,
		h = self._height,
	}
end

function TextWidget:paintTo(bb, x, y)
	--if not self._bb then
		--self:_render()
	--end
	--bb:blitFrom(self._bb, x, y, 0, 0, self._length, self._bb:getHeight())
	--@TODO Don't use kerning for monospaced fonts.    (houqp)
	renderUtf8Text(bb, x, y+self._height*0.7, self.face, self.text,
					true, self.bgcolor, self.fgcolor)
end

function TextWidget:free()
	if self._bb then
		self._bb:free()
		self._bb = nil
	end
end

--[[
A TextWidget that handles long text wrapping
--]]
TextBoxWidget = Widget:new{
	text = nil,
	face = nil,
	bgcolor = 0.0, -- [0.0, 1.0]
	fgcolor = 1.0, -- [0.0, 1.0]
	width = 400, -- in pixels
	height = nil,
	first_line = 1,
	virtual_line = 1, -- used by scroll bar
	line_height = 0.3, -- in em
	v_list = nil,
	_bb = nil,
	_length = 0,
}

function TextBoxWidget:init()
	local v_list = nil
	if self.height then
		v_list = self:_getCurrentVerticalList()
	else
		v_list = self:_getVerticalList()
	end
	self:_render(v_list)
end

function TextBoxWidget:_wrapGreedyAlg(h_list)
	local cur_line_width = 0
	local space_w = sizeUtf8Text(0, Screen:getWidth(), self.face, " ", true).x
	local cur_line = {}
	local v_list = {}

	for k,w in ipairs(h_list) do
		cur_line_width = cur_line_width + w.width
		local is_ascii = not w.word:match("[%z\194-\244][\128-\191]*")
		if cur_line_width <= self.width then
			cur_line_width = cur_line_width + (is_ascii and space_w or 0)
			table.insert(cur_line, w)
		else
			-- wrap to next line
			table.insert(v_list, cur_line)
			cur_line = {}
			cur_line_width = w.width + (is_ascii and space_w or 0)
			table.insert(cur_line, w)
		end
	end
	-- handle last line
	table.insert(v_list, cur_line)

	return v_list
end

function TextBoxWidget:_getVerticalList(alg)
	if self.vertical_list then
		return self.vertical_list
	end
	-- build horizontal list
	local h_list = {}
	for w in self.text:gmatch("[\33-\127\192-\255]+[\128-\191]*") do
		local word_box = {}
		word_box.word = w
		word_box.width = sizeUtf8Text(0, Screen:getWidth(), self.face, w, true).x
		table.insert(h_list, word_box)
	end

	-- @TODO check alg here 25.04 2012 (houqp)
	-- @TODO replace greedy algorithm with K&P algorithm  25.04 2012 (houqp)
	self.vertical_list = self:_wrapGreedyAlg(h_list)
	return self.vertical_list
end

function TextBoxWidget:_getCurrentVerticalList()
	local line_height = (1 + self.line_height) * self.face.size
	local v_list = self:_getVerticalList()
	local current_v_list = {}
	local height = 0
	for i = self.first_line, #v_list do
		if height < self.height - line_height then
			table.insert(current_v_list, v_list[i])
			height = height + line_height
		else
			break
		end
	end
	return current_v_list
end

function TextBoxWidget:_getPreviousVerticalList()
	local line_height = (1 + self.line_height) * self.face.size
	local v_list = self:_getVerticalList()
	local previous_v_list = {}
	local height = 0
	if self.first_line == 1 then
		return self:_getCurrentVerticalList()
	end
	self.virtual_line = self.first_line
	for i = self.first_line - 1, 1, -1 do
		if height < self.height - line_height then
			table.insert(previous_v_list, 1, v_list[i])
			height = height + line_height
			self.virtual_line = self.virtual_line - 1
		else
			break
		end
	end
	for i = self.first_line, #v_list do
		if height < self.height - line_height then
			table.insert(previous_v_list, v_list[i])
			height = height + line_height
		else
			break
		end
	end
	if self.first_line > #previous_v_list then
		self.first_line = self.first_line - #previous_v_list
	else
		self.first_line = 1
	end
	return previous_v_list
end

function TextBoxWidget:_getNextVerticalList()
	local line_height = (1 + self.line_height) * self.face.size
	local v_list = self:_getVerticalList()
	local current_v_list = self:_getCurrentVerticalList()
	local next_v_list = {}
	local height = 0
	if self.first_line + #current_v_list > #v_list then
		return current_v_list
	end
	self.virtual_line = self.first_line
	for i = self.first_line + #current_v_list, #v_list do
		if height < self.height - line_height then
			table.insert(next_v_list, v_list[i])
			height = height + line_height
			self.virtual_line = self.virtual_line + 1
		else
			break
		end
	end
	self.first_line = self.first_line + #current_v_list
	return next_v_list
end

function TextBoxWidget:_render(v_list)
	local font_height = self.face.size
	local line_height_px = self.line_height * font_height
	local space_w = sizeUtf8Text(0, Screen:getWidth(), self.face, " ", true).x
	local h = (font_height + line_height_px) * #v_list
	self._bb = Blitbuffer.new(self.width, h)
	local y = font_height
	local pen_x = 0
	for _,l in ipairs(v_list) do
		pen_x = 0
		for _,w in ipairs(l) do
			--@TODO Don't use kerning for monospaced fonts.    (houqp)
			-- refert to cb25029dddc42693cc7aaefbe47e9bd3b7e1a750 in master tree
			renderUtf8Text(self._bb, pen_x, y, self.face, w.word, 
							true, self.bgcolor, self.fgcolor)
			local is_ascii = not w.word:match("[%z\194-\244][\128-\191]*")
			pen_x = pen_x + w.width + (is_ascii and space_w or 0)
		end
		y = y + line_height_px + font_height
	end
--	-- if text is shorter than one line, shrink to text's width
--	if #v_list == 1 then
--		self.width = pen_x
--	end
end

function TextBoxWidget:getVirtualLineNum()
	return self.virtual_line
end

function TextBoxWidget:getAllLineCount()
	local v_list = self:_getVerticalList()
	return #v_list
end

function TextBoxWidget:getVisLineCount()
	local line_height = (1 + self.line_height) * self.face.size
	return math.floor(self.height / line_height)
end

function TextBoxWidget:scrollDown()
	local next_v_list = self:_getNextVerticalList()
	self:free()
	self:_render(next_v_list)
end

function TextBoxWidget:scrollUp()
	local previous_v_list = self:_getPreviousVerticalList()
	self:free()
	self:_render(previous_v_list)
end

function TextBoxWidget:getSize()
	if self.width and self.height then
		return Geom:new{ w = self.width, h = self.height}
	else
		return Geom:new{ w = self.width, h = self._bb:getHeight()}
	end
end

function TextBoxWidget:paintTo(bb, x, y)
	bb:blitFrom(self._bb, x, y, 0, 0, self.width, self._bb:getHeight())
end

function TextBoxWidget:free()
	if self._bb then
		self._bb:free()
		self._bb = nil
	end
end

--[[
FixedTextWidget
--]]
FixedTextWidget = TextWidget:new{}
function FixedTextWidget:getSize()
	local tsize = sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true)
	if not tsize then
		return Geom:new{}
	end
	self._length = tsize.x
	self._height = self.face.size
	return Geom:new{
		w = self._length,
		h = self._height,
	}
end

function FixedTextWidget:paintTo(bb, x, y)
	renderUtf8Text(bb, x, y+self._height, self.face, self.text,
					true, self.bgcolor, self.fgcolor)
end

--[[
Text widget with vertical scroll bar
--]]
ScrollTextWidget = InputContainer:new{
	text = nil,
	font_face = nil,
	width = 400,
	height = 300,
	scroll_bar_width = scaleByDPI(6),
	text_scroll_span = scaleByDPI(6),
	dialog = nil,
}

function ScrollTextWidget:init()
	self.text_widget = TextBoxWidget:new{
		text = self.text,
		face = self.font_face,
		width = self.width - self.scroll_bar_width - self.text_scroll_span,
		height = self.height
	}
	local visible_line_count = self.text_widget:getVisLineCount()
	local total_line_count = self.text_widget:getAllLineCount()
	self.v_scroll_bar = VerticalScrollBar:new{
		enable = visible_line_count < total_line_count,
		low = 0,
		high = visible_line_count/total_line_count,
		width = scaleByDPI(6),
		height = self.height,
	}
	local horizontal_group = HorizontalGroup:new{}
	table.insert(horizontal_group, self.text_widget)
	table.insert(horizontal_group, HorizontalSpan:new{width = scaleByDPI(6)})
	table.insert(horizontal_group, self.v_scroll_bar)
	self[1] = horizontal_group
	self.dimen = Geom:new(self[1]:getSize())
	if Device:isTouchDevice() then
		self.ges_events = {
			Swipe = {
				GestureRange:new{
					ges = "swipe",
					range = self.dimen,
				},
			},
		}
	end
end

function ScrollTextWidget:updateScrollBar(text)
	local virtual_line_num = text:getVirtualLineNum()
	local visible_line_count = text:getVisLineCount()
	local all_line_count = text:getAllLineCount()
	self.v_scroll_bar:set(
		(virtual_line_num - 1) / all_line_count,
		(virtual_line_num - 1 + visible_line_count) / all_line_count
	)
end

function ScrollTextWidget:onSwipe(arg, ges)
	if ges.direction == "north" then
		self.text_widget:scrollDown()
		self:updateScrollBar(self.text_widget)
	elseif ges.direction == "south" then
		self.text_widget:scrollUp()
		self:updateScrollBar(self.text_widget)
	end
	UIManager:setDirty(self.dialog, "partial")
	return true
end
