--[[--
BBoxWidget shows a bbox for page cropping.
]]

local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Math = require("optmath")
local Screen = Device.screen
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local BBoxWidget = InputContainer:extend{
    page_bbox = nil,
    screen_bbox = nil,
    linesize = Size.line.thick,
    fine_factor = 10,
    dimen = Geom:new(),
}

function BBoxWidget:init()
    self.page_bbox = self.document:getPageBBox(self.view.state.page)
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
    else
        self._confirm_stage = 1 -- 1 for left-top, 2 for right-bottom
        self.key_events.MoveIndicatorUp    = { { "Up" },    event="MoveIndicator", args = { 0, -1 } }
        self.key_events.MoveIndicatorDown  = { { "Down" },  event="MoveIndicator", args = { 0, 1 } }
        self.key_events.MoveIndicatorLeft  = { { "Left" },  event="MoveIndicator", args = { -1, 0 } }
        self.key_events.MoveIndicatorRight = { { "Right" }, event="MoveIndicator", args = { 1, 0 } }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.Select = { { "Press" } }
    end
end

function BBoxWidget:getSize()
    return self.view.dimen
end

function BBoxWidget:paintTo(bb, x, y)
    self.dimen = self.view.dimen:copy()
    self.dimen.x, self.dimen.y = x, y

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
    if self._confirm_stage == 1 then
        -- left top indicator
        self:_drawIndicator(bb, bbox.x0, bbox.y0)
    elseif self._confirm_stage == 2 then
        -- right bottom indicator
        self:_drawIndicator(bb, bbox.x1, bbox.y1)
    end
end

function BBoxWidget:_drawIndicator(bb, x, y)
    local rect = Geom:new({
        x = x - Size.item.height_default / 2,
        y = y - Size.item.height_default / 2,
        w = Size.item.height_default,
        h = Size.item.height_default,
    })
    -- paint big cross line +
    bb:invertRect(
        rect.x,
        rect.y + rect.h / 2 - Size.border.thick / 2,
        rect.w,
        Size.border.thick
    )
    bb:invertRect(
        rect.x + rect.w / 2 - Size.border.thick / 2,
        rect.y,
        Size.border.thick,
        rect.h
    )
end

-- transform page bbox to screen bbox
function BBoxWidget:getScreenBBox(page_bbox)
    local bbox = {}
    local scale = self.view.state.zoom
    local screen_offset = self.view.state.offset
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

    UIManager:setDirty(self.ui, "ui")
end

function BBoxWidget:onMoveIndicator(args)
    local dx, dy = unpack(args)
    local bbox = self.screen_bbox
    local move_distance = Size.item.height_default / 4
    local half_indicator_size = move_distance * 2
    -- mark edges dirty to redraw
    -- top edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y0 - move_distance,
        w = bbox.x1 - bbox.x0 + move_distance,
        h = move_distance * 2
    })
    -- left edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y0 - move_distance,
        w = move_distance * 2,
        h = bbox.y1 - bbox.y0 + move_distance,
    })
    -- right edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x1 - move_distance,
        y = bbox.y0 - move_distance,
        w = move_distance * 2,
        h = bbox.y1 - bbox.y0 + move_distance,
    })
    -- bottom edge
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - move_distance,
        y = bbox.y1 - move_distance,
        w = bbox.x1 - bbox.x0 + move_distance,
        h = move_distance * 2,
    })
    -- left top indicator
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x0 - half_indicator_size - move_distance,
        y = bbox.y0 - half_indicator_size - move_distance,
        w = half_indicator_size * 2 + move_distance,
        h = half_indicator_size * 2 + move_distance
    })
    -- bottom right indicator
    UIManager:setDirty(self.ui, "ui", Geom:new{
        x = bbox.x1 - half_indicator_size,
        y = bbox.y1 - half_indicator_size,
        w = half_indicator_size * 2 + move_distance,
        h = half_indicator_size * 2 + move_distance
    })
    if self._confirm_stage == 1 then
        local x = self.screen_bbox.x0 + dx * Size.item.height_default / 4
        local y = self.screen_bbox.y0 + dy * Size.item.height_default / 4
        local max_x = self.screen_bbox.x1 - Size.item.height_default
        local max_y = self.screen_bbox.y1 - Size.item.height_default
        x = (x > 0 and x) or 0
        x = (x < max_x and x) or max_x
        y = (y > 0 and y) or 0
        y = (y < max_y and y) or max_y
        self.screen_bbox.x0 = Math.round(x)
        self.screen_bbox.y0 = Math.round(y)
        return true
    elseif self._confirm_stage == 2 then
        local x = self.screen_bbox.x1 + dx * Size.item.height_default / 4
        local y = self.screen_bbox.y1 + dy * Size.item.height_default / 4
        local min_x = self.screen_bbox.x0 + Size.item.height_default
        local min_y = self.screen_bbox.y0 + Size.item.height_default
        x = (x > min_x and x) or min_x
        x = (x < Screen:getWidth() and x) or Screen:getWidth()
        y = (y > min_y and y) or min_y
        y = (y < Screen:getHeight() and y) or Screen:getHeight()
        self.screen_bbox.x1 = Math.round(x)
        self.screen_bbox.y1 = Math.round(y)
        return true
    end
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
    --- @fixme this is a dirty hack to disable hold gesture in page cropping
    -- since Kobo devices may append hold gestures to each swipe gesture rendering
    -- relative replacement impossible. See koreader/koreader#987 at Github.
    --self:adjustScreenBBox(ges)
    return true
end

function BBoxWidget:onConfirmAdjust(arg, ges)
    if self:inPageArea(ges) then
        self.ui:handleEvent(Event:new("ConfirmPageCrop"))
    end
    return true
end

function BBoxWidget:onClose()
    self.ui:handleEvent(Event:new("CancelPageCrop"))
    return true
end

function BBoxWidget:onSelect()
    if not self._confirm_stage or self._confirm_stage == 2 then
        self.ui:handleEvent(Event:new("ConfirmPageCrop"))
    else
        local bbox = self.screen_bbox
        self._confirm_stage = self._confirm_stage + 1
        -- left top indicator
        UIManager:setDirty(self.ui, "ui", Geom:new{
            x = bbox.x0 - Size.item.height_default / 2,
            y = bbox.y0 - Size.item.height_default / 2,
            w = Size.item.height_default,
            h = Size.item.height_default,
        })
        -- right bottom indicator
        UIManager:setDirty(self.ui, "ui", Geom:new{
            x = bbox.x1 - Size.item.height_default / 2,
            y = bbox.y1 - Size.item.height_default / 2,
            w = Size.item.height_default,
            h = Size.item.height_default,
        })
    end
    return true
end


return BBoxWidget
