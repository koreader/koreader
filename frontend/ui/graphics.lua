--[[
Draw a border

@x:  start position in x axis
@y:  start position in y axis
@w:  width of the border
@h:  height of the border
@bw: line width of the border
@c:  color for loading bar
@r:  radius of for border's corner (nil or 0 means right corner border)
--]]
function blitbuffer.paintBorder(bb, x, y, w, h, bw, c, r)
	x, y = math.ceil(x), math.ceil(y)
	h, w = math.ceil(h), math.ceil(w)
	if not r or r == 0 then
		bb:paintRect(x, y, w, bw, c)
		bb:paintRect(x, y+h-bw, w, bw, c)
		bb:paintRect(x, y+bw, bw, h - 2*bw, c)
		bb:paintRect(x+w-bw, y+bw, bw, h - 2*bw, c)
	else
		if h < 2*r then r = math.floor(h/2) end
		if w < 2*r then r = math.floor(w/2) end
		bb:paintRoundedCorner(x, y, w, h, bw, r, c)
		bb:paintRect(r+x, y, w-2*r, bw, c)
		bb:paintRect(r+x, y+h-bw, w-2*r, bw, c)
		bb:paintRect(x, r+y, bw, h-2*r, c)
		bb:paintRect(x+w-bw, r+y, bw, h-2*r, c)
	end
end


--[[
Fill a rounded corner rectangular area

@x:  start position in x axis
@y:  start position in y axis
@w:  width of the area
@h:  height of the area
@c:  color used to fill the area
@r:  radius of for four corners
--]]
function blitbuffer.paintRoundedRect(bb, x, y, w, h, c, r)
	x, y = math.ceil(x), math.ceil(y)
	h, w = math.ceil(h), math.ceil(w)
	if not r or r == 0 then
		bb:paintRect(x, y, w, h, c)
	else
		if h < 2*r then r = math.floor(h/2) end
		if w < 2*r then r = math.floor(w/2) end
		bb:paintBorder(x, y, w, h, r, c, r)
		bb:paintRect(x+r, y+r, w-2*r, h-2*r, c)
	end
end


--[[
Draw a progress bar according to following args:

@x:  start position in x axis
@y:  start position in y axis
@w:  width for progress bar
@h:  height for progress bar
@load_m_w: width margin for loading bar
@load_m_h: height margin for loading bar
@load_percent: progress in percent
@c:  color for loading bar
--]]
function blitbuffer.progressBar(bb, x, y, w, h,
								load_m_w, load_m_h, load_percent, c)
	if load_m_h*2 > h then
		load_m_h = h/2
	end
	bb:paintBorder(x, y, w, h, 2, 15)
	bb:paintRect(x+load_m_w, y+load_m_h,
				(w-2*load_m_w)*load_percent, (h-2*load_m_h), c)
end



------------------------------------------------
-- Start of Cursor class
------------------------------------------------

Cursor = {
	x_pos = 0,
	y_pos = 0,
	--color = 15,
	h = 10,
	w = nil,
	line_w = nil,
	is_cleared = true,
}

function Cursor:new(o)
	o = o or {}
	o.x_pos = o.x_pos or self.x_pos
	o.y_pos = o.y_pos or self.y_pos
	o.line_width_factor = o.line_width_factor or 10

	setmetatable(o, self)
	self.__index = self

	o:setHeight(o.h or self.h)
	return o
end

function Cursor:setHeight(h)
	self.h = h
	self.w = self.h / 3
	self.line_w = math.floor(self.h / self.line_width_factor)
end

function Cursor:_draw(x, y)
	local up_down_width = math.floor(self.line_w / 2)
	local body_h = self.h - (up_down_width * 2)
	-- paint upper horizontal line
	fb.bb:invertRect(x, y, self.w, up_down_width)
	-- paint middle vertical line
	fb.bb:invertRect(x + (self.w / 2) - up_down_width, y + up_down_width,
							self.line_w, body_h)
	-- paint lower horizontal line
	fb.bb:invertRect(x, y + body_h + up_down_width, self.w, up_down_width)
end

function Cursor:draw()
	if self.is_cleared then
		self.is_cleared = false
		self:_draw(self.x_pos, self.y_pos)
	end
end

function Cursor:clear()
	if not self.is_cleared then
		self.is_cleared = true
		self:_draw(self.x_pos, self.y_pos)
	end
end

function Cursor:move(x_off, y_off)
	self.x_pos = self.x_pos + x_off
	self.y_pos = self.y_pos + y_off
end

function Cursor:moveHorizontal(x_off)
	self.x_pos = self.x_pos + x_off
end

function Cursor:moveVertical(x_off)
	self.y_pos = self.y_pos + y_off
end

function Cursor:moveAndDraw(x_off, y_off)
	self:clear()
	self:move(x_off, y_off)
	self:draw()
end

function Cursor:moveTo(x_pos, y_pos)
	self.x_pos = x_pos
	self.y_pos = y_pos
end

function Cursor:moveToAndDraw(x_pos, y_pos)
	self:clear()
	self.x_pos = x_pos
	self.y_pos = y_pos
	self:draw()
end

function Cursor:moveHorizontalAndDraw(x_off)
	self:clear()
	self:move(x_off, 0)
	self:draw()
end

function Cursor:moveVerticalAndDraw(y_off)
	self:clear()
	self:move(0, y_off)
	self:draw()
end

