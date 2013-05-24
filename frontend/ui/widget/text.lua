require "ui/widget/base"
require "ui/rendertext"


--[[
A TextWidget puts a string on a single line
--]]
TextWidget = Widget:new{
	text = nil,
	face = nil,
	color = 15,
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
	renderUtf8Text(bb, x, y+self._height*0.7, self.face, self.text, true)
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
	color = 15,
	width = 400, -- in pixels
	line_height = 0.3, -- in em
	v_list = nil,
	_bb = nil,
	_length = 0,
}

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
	-- build horizontal list
	h_list = {}
	for w in self.text:gmatch("[\33-\127\192-\255]+[\128-\191]*") do
		word_box = {}
		word_box.word = w
		word_box.width = sizeUtf8Text(0, Screen:getWidth(), self.face, w, true).x
		table.insert(h_list, word_box)
	end

	-- @TODO check alg here 25.04 2012 (houqp)
	-- @TODO replace greedy algorithm with K&P algorithm  25.04 2012 (houqp)
	return self:_wrapGreedyAlg(h_list)
end

function TextBoxWidget:_render()
	self.v_list = self:_getVerticalList()
	local v_list = self.v_list
	local font_height = self.face.size
	local line_height_px = self.line_height * font_height
	local space_w = sizeUtf8Text(0, Screen:getWidth(), self.face, " ", true).x
	local h = (font_height + line_height_px) * #v_list - line_height_px
	self._bb = Blitbuffer.new(self.width, h)
	local y = font_height
	local pen_x = 0
	for _,l in ipairs(v_list) do
		pen_x = 0
		for _,w in ipairs(l) do
			--@TODO Don't use kerning for monospaced fonts.    (houqp)
			-- refert to cb25029dddc42693cc7aaefbe47e9bd3b7e1a750 in master tree
			renderUtf8Text(self._bb, pen_x, y*0.8, self.face, w.word, true)
			local is_ascii = not w.word:match("[%z\194-\244][\128-\191]*")
			pen_x = pen_x + w.width + (is_ascii and space_w or 0)
		end
		y = y + line_height_px + font_height
	end
	-- if text is shorter than one line, shrink to text's width
	if #v_list == 1 then
		self.width = pen_x
	end
end

function TextBoxWidget:getSize()
	if not self._bb then
		self:_render()
	end
	return { w = self.width, h = self._bb:getHeight() }
end

function TextBoxWidget:paintTo(bb, x, y)
	if not self._bb then
		self:_render()
	end
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
	renderUtf8Text(bb, x, y+self._height, self.face, self.text, true)
end


