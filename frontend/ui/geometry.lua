--[[
2D Geometry utilities

all of these apply to full rectangles { x = ..., y = ..., w = ..., h = ... }

some behaviour is defined for points { x = ..., y = ... }
some behaviour is defined for dimensions { w = ..., h = ... }

just use it on simple tables that have x, y and/or w, h
or define your own types using this as a metatable
]]--
Geom = {
	x = 0,
	y = 0,
	w = 0,
	h = 0
}

function Geom:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Geom:copy()
	local n = Geom:new()
	n.x = self.x
	n.y = self.y
	n.w = self.w
	n.h = self.h
	return n
end

function Geom:__tostring()
	return self.w.."x"..self.h.."+"..self.x.."+"..self.y
end

--[[
offset rectangle or point by relative values
]]--
function Geom:offsetBy(dx, dy)
	self.x = self.x + dx
	self.y = self.y + dy
	return self
end

--[[
offset rectangle or point to certain coordinates
]]--
function Geom:offsetTo(x, y)
	self.x = x
	self.y = y
	return self
end

--[[
scale rectangle (grow to bottom and to the right) or dimension

if a single factor is given, it is applied to both width and height
]]--
function Geom:scaleBy(zx, zy)
	self.w = self.w * zx
	self.h = self.h * (zy or zx)
	return self
end

--[[
this method also takes care of x and y
]]--
function Geom:transformByScale(zx, zy)
	self.x = self.x * zx
	self.y = self.y * (zx or zy)
	self:scaleBy(zx, zy)
end

--[[
return size of geom
]]--
function Geom:sizeof()
	if not self.w or not self.h then
		return 0
	else
		return self.w * self.h
	end
end

--[[
enlarges or shrinks dimensions or rectangles

note that for rectangles the offset stays the same
]]--
function Geom:changeSizeBy(dw, dh)
	self.w = self.w + dw
	self.h = self.h + dh
	return self
end

--[[
return the outer rectangle that contains both us and a given rectangle

works for rectangles, dimensions and points
]]--
function Geom:combine(rect_b)
	local combined = self:copy()
	if not rect_b or rect_b:sizeof() == 0 then return combined end
	if combined.x > rect_b.x then
		combined.x = rect_b.x
	end
	if combined.y > rect_b.y then
		combined.y = rect_b.y
	end
	if self.x + self.w > rect_b.x + rect_b.w then
		combined.w = self.x + self.w - combined.x
	else
		combined.w = rect_b.x + rect_b.w - combined.x
	end
	if self.y + self.h > rect_b.y + rect_b.h then
		combined.h = self.y + self.h - combined.y
	else
		combined.h = rect_b.y + rect_b.h - combined.y
	end
	return combined
end

--[[
returns a rectangle for the part that we and a given rectangle share

TODO: what happens if there is no rectangle shared? currently behaviour is undefined.
]]--
function Geom:intersect(rect_b)
	-- make a copy of self
	local intersected = self:copy()
	if self.x < rect_b.x then
		intersected.x = rect_b.x
	end
	if self.y < rect_b.y then
		intersected.y = rect_b.y
	end
	if self.x + self.w < rect_b.x + rect_b.w then
		intersected.w = self.x + self.w - intersected.x
	else
		intersected.w = rect_b.x + rect_b.w - intersected.x
	end
	if self.y + self.h < rect_b.y + rect_b.h then
		intersected.h = self.y + self.h - intersected.y
	else
		intersected.h = rect_b.y + rect_b.h - intersected.y
	end
	return intersected
end

--[[
return true if self does not share any area with rect_b
]]--
function Geom:notIntersectWith(rect_b)
	if (self.x >= (rect_b.x + rect_b.w))
	or (self.y >= (rect_b.y + rect_b.h))
	or (rect_b.x >= (self.x + self.w))
	or (rect_b.y >= (self.y + self.h)) then
		return true
	end
	return false
end

--[[
set size of dimension or rectangle to size of given dimension/rectangle
]]--
function Geom:setSizeTo(rect_b)
	self.w = rect_b.w
	self.h = rect_b.h
	return self
end

--[[
check whether rect_b is within current rectangle

works for dimensions, too
for points, it is basically an equality check
]]--
function Geom:contains(rect_b)
	if self.x <= rect_b.x
	and self.y <= rect_b.y
	and self.x + self.w >= rect_b.x + rect_b.w
	and self.y + self.h >= rect_b.y + rect_b.h
	then
		return true
	end
	return false
end

--[[
check for equality

works for rectangles, points, dimensions
]]--
function Geom:__eq(rect_b)
	if self.x == rect_b.x
	and self.y == rect_b.y
	and self:equalSize(rect_b)
	then
		return true
	end
	return false
end

--[[
check size of dimension/rectangle for equality
]]--
function Geom:equalSize(rect_b)
	if self.w == rect_b.w
	and self.h == rect_b.h
	then
		return true
	end
	return false
end

--[[
check if our size is smaller than the size of the given dimension/rectangle
]]--
function Geom:__lt(rect_b)
	DEBUG("lt:",self,rect_b)
	if self.w < rect_b.w and self.h < rect_b.h then
DEBUG("lt+")
		return true
	end
DEBUG("lt-")
	return false
end

--[[
check if our size is smaller or equal the size of the given dimension/rectangle
]]--
function Geom:__le(rect_b)
	if self.w <= rect_b.w and self.h <= rect_b.h then
		return true
	end
	return false
end

--[[
offset the current rectangle by dx, dy while fitting it into the space
of a given rectangle

this can also be called with dx=0 and dy=0, which will fit the current
rectangle into the given rectangle
]]--
function Geom:offsetWithin(rect_b, dx, dy)
	-- check size constraints and shrink us when we're too big
	if self.w > rect_b.w then
		self.w = rect_b.w
	end
	if self.h > rect_b.h then
		self.h = rect_b.h
	end
	-- offset
	self.x = self.x + dx
	self.y = self.y + dy
	-- check offsets
	if self.x < rect_b.x then
		self.x = rect_b.x
	end
	if self.y < rect_b.y then
		self.y = rect_b.y
	end
	if self.x + self.w > rect_b.x + rect_b.w then
		self.x = rect_b.x + rect_b.w - self.w
	end
	if self.y + self.h > rect_b.y + rect_b.h then
		self.y = rect_b.y + rect_b.h - self.h
	end
end

function Geom:shrinkInside(rect_b, dx, dy)
	self:offsetBy(dx, dy)
	return self:intersect(rect_b)
end

--[[
return the Euclidean distance between two geoms
]]--
function Geom:distance(geom)
	return math.sqrt(math.pow(self.x - geom.x, 2) + math.pow(self.y - geom.y, 2))
end

--[[
return the midpoint of two geoms
]]--
function Geom:midpoint(geom)
	return Geom:new{
		x = (self.x + geom.x) / 2,
		y = (self.y + geom.y) / 2,
		w = 0, h = 0,
	}
end

