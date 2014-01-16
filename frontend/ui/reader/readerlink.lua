local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local Event = require("ui/event")
local DEBUG = require("dbg")

local ReaderLink = InputContainer:new{}

function ReaderLink:init()
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderLink:initGesListener()
	if Device:isTouchDevice() then
		self.ges_events = {
			Tap = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
		}
	end
end

function ReaderLink:onSetDimensions(dimen)
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderLink:onTap(arg, ges)
	local function inside_box(pos, box)
		if pos then
			local x, y = pos.x, pos.y
			if box.x <= x and box.y <= y 
				and box.x + box.w >= x 
				and box.y + box.h >= y then
				return true
			end
		end
	end
	if self.view.links then
		local pos = self.view:screenToPageTransform(ges.pos)
		for i = 1, #self.view.links do
			local link = self.view.links[i]
			-- enlarge tappable link box
			local lbox = Geom:new{
				x = link.start_x - Screen:scaleByDPI(15),
				y = link.start_y - Screen:scaleByDPI(15),
				w = link.end_x - link.start_x + Screen:scaleByDPI(30),
				h = link.end_y - link.start_y > 0 
				        and link.end_y - link.start_y + Screen:scaleByDPI(30) 
				        or Screen:scaleByDPI(50),
			}
			if inside_box(pos, lbox) then
				DEBUG("goto link", link)
				self.document:gotoLink(link.section)
				self.ui:handleEvent(Event:new("UpdateXPointer"))
				return true
			end
		end
	end
end

return ReaderLink
