local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local ImageWidget = require("ui/widget/imagewidget")
local RenderImage = require("ui/renderimage")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local CLOCK_FACE_BB = RenderImage:renderImageFile("plugins/clock.koplugin/face.png")
local HOURS_HAND_BB = RenderImage:renderImageFile("plugins/clock.koplugin/hours.png")
local MINUTES_HAND_BB = RenderImage:renderImageFile("plugins/clock.koplugin/minutes.png")

local function rotate_point(point_x, point_y, center_x, center_y, angle_rad)
    local sin, cos, floor = math.sin, math.cos, math.floor
    local s, c = sin(angle_rad), cos(angle_rad)
    local x, y = (point_x - center_x), (point_y - center_y)
    local new_x, new_y = (x * c - y * s), (x * s + y * c)
    return floor(center_x + new_x + 0.5), floor(center_y + new_y + 0.5)
end

local function rotate_bb(bb, center_x, center_y, angle_rad)
    local w, h = bb:getWidth(), bb:getHeight()
    local rot_bb = Blitbuffer.new(w, h, bb:getType())
    w, h = w - 1, h - 1
    for x = 0, w do
        for y = 0, h do
            local old_x, old_y = rotate_point(x, y, center_x, center_y, -angle_rad)
            if old_x >= 0 and old_x <= w and old_y >= 0 and old_y <= h then
                rot_bb:setPixel(x, y, bb:getPixel(old_x, old_y))
            end
        end
    end
    return rot_bb
end

local ClockWidget = WidgetContainer:new{
    width = Screen:scaleBySize(200),
    height = Screen:scaleBySize(200),
    padding = Size.padding.large,
    scale_factor = 0
}

function ClockWidget:init()
    local padding = self.padding
    local width, height = self.width - 2 * padding, self.height - 2 * padding

    self.face = CenterContainer:new{
        dimen = self:getSize(),
        ImageWidget:new{
            image = CLOCK_FACE_BB,
            width = width,
            height = height,
            scale_factor = self.scale_factor,
            alpha = true
        },
    }
    self:_updateHands()
end

function ClockWidget:paintTo(bb, x, y)
    local hands = self._hands[60 * tonumber(os.date("%H")) + tonumber(os.date("%M"))]
    bb:fill(Blitbuffer.COLOR_WHITE)
    local size = self:getSize()
    x = x + self.width / 2
    y = y + self.height / 2
    self.face:paintTo(bb, x, y)
    hands.hours:paintTo(bb, x, y)
    hands.minutes:paintTo(bb, x, y)
    if Screen.night_mode then
        bb:invertRect(x, y, size.w, size.h)
    end
end

function ClockWidget:_prepare_hands(hours, minutes)
    local idx = hours * 60 + minutes
    if self._hands[idx] then return end
    self._hands[idx] = {}
    local hour_rad, minute_rad = math.pi / 6, math.pi / 30
    local padding = self.padding
    local width, height = self.width - 2 * padding, self.height - 2 * padding

    local hours_hand_widget = ImageWidget:new{
        image = rotate_bb(
            HOURS_HAND_BB,
            HOURS_HAND_BB:getWidth() / 2,
            HOURS_HAND_BB:getHeight() / 2,
            (hours + minutes/60) * hour_rad
        ),
        width = width,
        height = height,
        scale_factor = self.scale_factor,
        alpha = true,
    }
    local minutes_hand_widget = ImageWidget:new{
        image = rotate_bb(
            MINUTES_HAND_BB,
            MINUTES_HAND_BB:getWidth() / 2,
            MINUTES_HAND_BB:getHeight() / 2,
            minutes * minute_rad
        ),
        width = width,
        height = height,
        scale_factor = self.scale_factor,
        alpha = true,
    }

    self._hands[idx].hours = CenterContainer:new{
        dimen = self:getSize(),
        hours_hand_widget,
    }
    self._hands[idx].minutes = CenterContainer:new{
        dimen = self:getSize(),
        minutes_hand_widget,
    }
    local n_hands = 0
    for _ in pairs(self._hands) do n_hands = n_hands + 1 end
    logger.dbg("ClockWidget: hands ready for", hours, minutes, ":", n_hands, "position(s) in memory.")
end

function ClockWidget:_updateHands()
    self._hands = self._hands or {}
    local hours, minutes = tonumber(os.date("%H")), tonumber(os.date("%M"))
    local floor, fmod = math.floor, math.fmod
    --  We prepare this minute's hands at once (if necessary).
    self:_prepare_hands(hours, minutes)
    --  Then we schedule preparation of next two minutes' hands.
    for i = 1, 2 do
        local fut_minutes, fut_hours
        fut_minutes = minutes + i
        fut_hours = fmod(hours + floor(fut_minutes / 60), 24)
        fut_minutes = fmod(fut_minutes, 60)
        UIManager:scheduleIn(i * 10, function() self:_prepare_hands(fut_hours, fut_minutes) end)
    end
    --  Then we schedule removing of past minutes' hands.
    UIManager:scheduleIn(30, function()
        local idx = hours * 60 + minutes
        for k in pairs(self._hands) do
            if (idx < 24 * 60 - 2) and (k - idx < 0) or (k - idx > 2) then
                self._hands[k] = nil
            end
        end
    end)
end

function ClockWidget:onShow()
    self:_updateHands()
    self:setupAutoRefreshTime()
end

function ClockWidget:setupAutoRefreshTime()
    if not self.autoRefreshTime then
        self.autoRefreshTime = function()
            UIManager:setDirty("all", function()
                return "ui", self.dimen, true
            end)
            self:_updateHands()
            UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.autoRefreshTime)
        end
    end
    self.onCloseWidget = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    self.onSuspend = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    self.onResume = function()
        self.autoRefreshTime()
    end
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.autoRefreshTime)
end

return ClockWidget
