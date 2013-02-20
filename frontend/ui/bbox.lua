require "math"

--[[
BBoxWidget shows a bbox for page cropping
]]
BBoxWidget = InputContainer:new{
	page_bbox = nil,
	screen_bbox = nil,
	linesize = 2,
}

function BBoxWidget:init()
	self.page_bbox = self.document:getPageBBox(self.view.state.page)
	--DEBUG("used page bbox on page", self.view.state.page, self.page_bbox)
	if Device:isTouchDevice() then
		self.ges_events = {
			TapAdjust = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			PanAdjust = {
				GestureRange:new{
					ges = "pan",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			ConfirmCrop = {
				GestureRange:new{
					ges = "double_tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			CancelCrop = {
				GestureRange:new{
					ges = "hold",
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

function BBoxWidget:getSize()
	return Geom:new{
		x = 0, y = 0,
		w = Screen:getWidth(),
		h = Screen:getHeight()
	}
end

function BBoxWidget:paintTo(bb, x, y)
	self.screen_bbox = self.screen_bbox or self:page_to_screen()
	local bbox = self.screen_bbox
	-- upper_left
	bb:invertRect(bbox.x0 + self.linesize, bbox.y0, bbox.x1 - bbox.x0, self.linesize)
	bb:invertRect(bbox.x0, bbox.y0, self.linesize, bbox.y1 - bbox.y0 + self.linesize)
	-- bottom_right
	bb:invertRect(bbox.x0 + self.linesize, bbox.y1, bbox.x1 - bbox.x0 - self.linesize, self.linesize)
	bb:invertRect(bbox.x1, bbox.y0 + self.linesize, self.linesize, bbox.y1 - bbox.y0)
end

-- transform page bbox to screen bbox
function BBoxWidget:page_to_screen()
	local bbox = {}
	local scale = self.view.state.zoom
	local screen_offset = self.view.state.offset
	--DEBUG("screen offset in page_to_screen", screen_offset)
	bbox.x0 = self.page_bbox.x0 * scale + screen_offset.x
	bbox.y0 = self.page_bbox.y0 * scale + screen_offset.y
	bbox.x1 = self.page_bbox.x1 * scale + screen_offset.x
	bbox.y1 = self.page_bbox.y1 * scale + screen_offset.y
	return bbox
end

-- transform screen bbox to page bbox
function BBoxWidget:screen_to_page()
	local bbox = {}
	local scale = self.view.state.zoom
	local screen_offset = self.view.state.offset
	--DEBUG("screen offset in screen_to_page", screen_offset)
	bbox.x0 = (self.screen_bbox.x0 - screen_offset.x) / scale
	bbox.y0 = (self.screen_bbox.y0 - screen_offset.y) / scale
	bbox.x1 = (self.screen_bbox.x1 - screen_offset.x) / scale
	bbox.y1 = (self.screen_bbox.y1 - screen_offset.y) / scale
	return bbox
end

function BBoxWidget:onAdjustScreenBBox(ges, rate)
	--DEBUG("adjusting crop bbox with pos", ges.pos)
	local bbox = self.screen_bbox
	local upper_left = Geom:new{ x = bbox.x0, y = bbox.y0}
	local upper_right = Geom:new{ x = bbox.x1, y = bbox.y0}
	local bottom_left = Geom:new{ x = bbox.x0, y = bbox.y1}
	local bottom_right = Geom:new{ x = bbox.x1, y = bbox.y1}
	local corners = {upper_left, upper_right, bottom_left, bottom_right}
	table.sort(corners, function(a,b)
		return a:distance(ges.pos) < b:distance(ges.pos)
	end)
	if corners[1] == upper_left then
		upper_left.x = ges.pos.x
		upper_left.y = ges.pos.y
	elseif corners[1] == bottom_right then
		bottom_right.x = ges.pos.x
		bottom_right.y = ges.pos.y
	elseif corners[1] == upper_right then
		bottom_right.x = ges.pos.x
		upper_left.y = ges.pos.y
	elseif corners[1] == bottom_left then
		upper_left.x = ges.pos.x
		bottom_right.y = ges.pos.y
	end
	self.screen_bbox = {
		x0 = upper_left.x, 
		y0 = upper_left.y,
		x1 = bottom_right.x,
		y1 = bottom_right.y
	}
	if rate then
		local last_time = self.last_time or {0, 0}
		local this_time = { util.gettime() }
		local elap_time = (this_time[1] - last_time[1]) * 1000 + (this_time[2] - last_time[2]) / 1000  -- in millisec
		if elap_time > 1000 / rate then
			UIManager.repaint_all = true
			self.last_time = this_time
		end
	else
		UIManager.repaint_all = true
	end
end

function BBoxWidget:onTapAdjust(arg, ges)
	self:onAdjustScreenBBox(ges)
	return true
end

function BBoxWidget:onPanAdjust(arg, ges)
	-- up to 3 updates per second
	self:onAdjustScreenBBox(ges, 3.0)
	return true
end

function BBoxWidget:onConfirmCrop()
	local new_bbox = self:screen_to_page()
	self.ui:handleEvent(Event:new("ConfirmPageCrop", new_bbox))
	return true
end

function BBoxWidget:onCancelCrop()
	UIManager:close(self.crop_bbox)
	self.ui:handleEvent(Event:new("CancelPageCrop"))
	return true
end
