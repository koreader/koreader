
blitbuffer.paintBorder = function (bb, x, y, w, h, bw, c)
	bb:paintRect(x, y, w, bw, c)
	bb:paintRect(x, y+h-bw, w, bw, c)
	bb:paintRect(x, y+bw, bw, h - 2*bw, c)
	bb:paintRect(x+w-bw, y+bw, bw, h - 2*bw, c)
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
blitbuffer.progressBar = function (bb, x, y, w, h, 
									load_m_w, load_m_h, load_percent, c)
	if load_m_h*2 > h then
		load_m_h = h/2
	end
	blitbuffer.paintBorder(fb.bb, x, y, w, h, 2, 15)
	fb.bb:paintRect(x+load_m_w, y+load_m_h, 
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
}

function Cursor:new(o)
	o = o or {}
	o.x_pos = o.x_pos or self.x_pos 
	o.y_pos = o.y_pos or self.y_pos 

	setmetatable(o, self)
	self.__index = self

	o:setHeight(o.h or self.h)
	return o
end

function Cursor:setHeight(h)
	self.h = h
	self.w = self.h / 3
	self.line_w = math.floor(self.h / 10)
end

function Cursor:_draw(x, y)
	local body_h = self.h - self.line_w
	-- paint upper horizontal line
	fb.bb:invertRect(x, y, self.w, self.line_w/2)
	-- paint middle vertical line
	fb.bb:invertRect(x+(self.w/2)-(self.line_w/2), y+self.line_w/2, 
							self.line_w, body_h)
	-- paint lower horizontal line
	fb.bb:invertRect(x, y+body_h+self.line_w/2, self.w, self.line_w/2)
end

function Cursor:draw()
	self:_draw(self.x_pos, self.y_pos)
end

function Cursor:clear()
	self:_draw(self.x_pos, self.y_pos)
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

