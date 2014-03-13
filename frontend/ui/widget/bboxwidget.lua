local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Math = require("optmath")
local DEBUG = require("dbg")

--[[
BBoxWidget shows a bbox for page cropping
]]
local BBoxWidget = InputContainer:new{
    page_bbox = nil,
    screen_bbox = nil,
    linesize = 2,
    fine_factor = 10,
}

function BBoxWidget:init()
    self.page_bbox = self.document:getPageBBox(self.view.state.page)
    --DEBUG("used page bbox on page", self.view.state.page, self.page_bbox)
    if Device:isTouchDevice() then
        self.ges_events = {
            TapAdjust = {
                GestureRange:new{
                    ges = "tap",
                    range = self.view.dimen,
                }
            },
            SwipeAdjust = {
                GestureRange:new{
                    ges = "swipe",
                    range = self.view.dimen,
                }
            },
            HoldAdjust = {
                GestureRange:new{
                    ges = "hold",
                    range = self.view.dimen,
                }
            },
            ConfirmAdjust = {
                GestureRange:new{
                    ges = "double_tap",
                    range = self.view.dimen,
                }
            }
        }
    end
end

function BBoxWidget:getSize()
    return self.view.dimen
end

function BBoxWidget:paintTo(bb, x, y)
    -- As getScreenBBox uses view states, screen_bbox initialization is postponed.
    self.screen_bbox = self.screen_bbox or self:getScreenBBox(self.page_bbox)
    local bbox = self.screen_bbox
    -- top edge
    bb:invertRect(bbox.x0 + self.linesize, bbox.y0, bbox.x1 - bbox.x0, self.linesize)
    -- bottom edge
    bb:invertRect(bbox.x0 + self.linesize, bbox.y1, bbox.x1 - bbox.x0 - self.linesize, self.linesize)
    -- left edge
    bb:invertRect(bbox.x0, bbox.y0, self.linesize, bbox.y1 - bbox.y0 + self.linesize)
    -- right edge
    bb:invertRect(bbox.x1, bbox.y0 + self.linesize, self.linesize, bbox.y1 - bbox.y0)
end

-- transform page bbox to screen bbox
function BBoxWidget:getScreenBBox(page_bbox)
    local bbox = {}
    local scale = self.view.state.zoom
    local screen_offset = self.view.state.offset
    --DEBUG("screen offset in page_to_screen", screen_offset)
    bbox.x0 = Math.round(page_bbox.x0 * scale + screen_offset.x)
    bbox.y0 = Math.round(page_bbox.y0 * scale + screen_offset.y)
    bbox.x1 = Math.round(page_bbox.x1 * scale + screen_offset.x)
    bbox.y1 = Math.round(page_bbox.y1 * scale + screen_offset.y)
    return bbox
end

-- transform screen bbox to page bbox
function BBoxWidget:getPageBBox(screen_bbox)
    local bbox = {}
    local scale = self.view.state.zoom
    local screen_offset = self.view.state.offset
    --DEBUG("screen offset in screen_to_page", screen_offset)
    bbox.x0 = Math.round((screen_bbox.x0 - screen_offset.x) / scale)
    bbox.y0 = Math.round((screen_bbox.y0 - screen_offset.y) / scale)
    bbox.x1 = Math.round((screen_bbox.x1 - screen_offset.x) / scale)
    bbox.y1 = Math.round((screen_bbox.y1 - screen_offset.y) / scale)
    return bbox
end

function BBoxWidget:inPageArea(ges)
    local offset = self.view.state.offset
    local page_area = self.view.page_area
    local page_dimen = Geom:new{ x = offset.x, y = offset.y, h = page_area.h, w = page_area.w}
    return not ges.pos:notIntersectWith(page_dimen)
end

function BBoxWidget:adjustScreenBBox(ges, relative)
    --DEBUG("adjusting crop bbox with pos", ges.pos)
    if not self:inPageArea(ges) then return end
    local bbox = self.screen_bbox
    local upper_left = Geom:new{ x = bbox.x0, y = bbox.y0}
    local upper_right = Geom:new{ x = bbox.x1, y = bbox.y0}
    local bottom_left = Geom:new{ x = bbox.x0, y = bbox.y1}
    local bottom_right = Geom:new{ x = bbox.x1, y = bbox.y1}
    local upper_center = Geom:new{ x = (bbox.x0 + bbox.x1) / 2, y = bbox.y0}
    local bottom_center = Geom:new{ x = (bbox.x0 + bbox.x1) / 2, y = bbox.y1}
    local right_center = Geom:new{ x = bbox.x1, y = (bbox.y0 + bbox.y1) / 2}
    local left_center = Geom:new{ x = bbox.x0, y = (bbox.y0 + bbox.y1) / 2}
    local anchors = {
        upper_left, upper_center,     upper_right,
        left_center,                 right_center,
        bottom_left, bottom_center, bottom_right,
    }
    local _, nearest = Math.tmin(anchors, function(a,b)
        return a:distance(ges.pos) > b:distance(ges.pos)
    end)
    --DEBUG("nearest anchor", nearest)
    if nearest == upper_left then
        upper_left.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_right then
        bottom_right.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_right then
        bottom_right.x = ges.pos.x
        upper_left.y = ges.pos.y
    elseif nearest == bottom_left then
        upper_left.x = ges.pos.x
        bottom_right.y = ges.pos.y
    elseif nearest == upper_center then
        if relative then
            local delta = 0
            if ges.direction == "north" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "south" then
                delta = ges.distance / self.fine_factor
            end
            upper_left.y = upper_left.y + delta
        else
            upper_left.y = ges.pos.y
        end
    elseif nearest == right_center then
        if relative then
            local delta = 0
            if ges.direction == "west" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "east" then
                delta = ges.distance / self.fine_factor
            end
            bottom_right.x = bottom_right.x + delta
        else
            bottom_right.x = ges.pos.x
        end
    elseif nearest == bottom_center then
        if relative then
            local delta = 0
            if ges.direction == "north" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "south" then
                delta = ges.distance / self.fine_factor
            end
            bottom_right.y = bottom_right.y + delta
        else
            bottom_right.y = ges.pos.y
        end
    elseif nearest == left_center then
        if relative then
            local delta = 0
            if ges.direction == "west" then
                delta = -ges.distance / self.fine_factor
            elseif ges.direction == "east" then
                delta = ges.distance / self.fine_factor
            end
            upper_left.x = upper_left.x + delta
        else
            upper_left.x = ges.pos.x
        end
    end
    self.screen_bbox = {
        x0 = Math.round(upper_left.x),
        y0 = Math.round(upper_left.y),
        x1 = Math.round(bottom_right.x),
        y1 = Math.round(bottom_right.y)
    }

    UIManager.repaint_all = true
end

function BBoxWidget:getModifiedPageBBox()
    return self:getPageBBox(self.screen_bbox)
end

function BBoxWidget:onTapAdjust(arg, ges)
    self:adjustScreenBBox(ges)
    return true
end

function BBoxWidget:onSwipeAdjust(arg, ges)
    self:adjustScreenBBox(ges, true)
    return true
end

function BBoxWidget:onHoldAdjust(arg, ges)
    self:adjustScreenBBox(ges)
    return true
end

function BBoxWidget:onConfirmAdjust(arg, ges)
    if self:inPageArea(ges) then
        self.ui:handleEvent(Event:new("ConfirmPageCrop"))
    end
    return true
end

return BBoxWidget
