-- touch probe utility
-- usage: ./luajit tools/kobo_touch_probe.lua

require "defaults"
package.path = "common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "common/?.so;common/?.dll;/usr/lib/lua/?.so;" .. package.cpath

local DataStorage = require("datastorage")
local _ = require("gettext")

-- read settings and check for language override
-- but don't re-read if already done, to avoid causing problems for unit tests
-- has to be done before requiring other files because
-- they might call gettext on load
if G_reader_settings == nil then
    G_reader_settings = require("luasettings"):open(
        DataStorage:getDataDir().."/settings.reader.lua")
end
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
--dbg:turnOn()

local TouchProbe = InputContainer:extend{
    curr_probe_step = 1,
}

function TouchProbe:init()
    self.ges_events.TapProbe = {
        GestureRange:new{
            ges = "tap",
        }
    }
    self.image_widget = ImageWidget:new{
        file = "tools/kobo-touch-probe.png",
    }
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local img_w, img_h = self.image_widget:getSize().w, self.image_widget:getSize().h
    self.probe_steps = {
        {
            hint_text = _("Tap the lower right corner"),
            hint_icon_pos = {
                x = screen_w-img_w,
                y = screen_h-img_h,
            }
        },
        {
            hint_text = _("Tap the upper right corner"),
            hint_icon_pos = {
                x = screen_w-img_w,
                y = 0,
            }
        },
    }
    self.hint_text_widget = TextWidget:new{
        text = '',
        face = Font:getFace("cfont", 30),
    }
    self[1] = FrameContainer:new{
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Screen:getSize(),
            CenterContainer:new{
                dimen = Screen:getSize(),
                self.hint_text_widget,
            },
            self.image_widget,
        },
    }
    self:updateProbeInstruction()
end

function TouchProbe:updateProbeInstruction()
    local probe_step = self.probe_steps[self.curr_probe_step]
    self.image_widget.overlap_offset = {
        probe_step.hint_icon_pos.x,
        probe_step.hint_icon_pos.y,
    }
    self.hint_text_widget:setText(probe_step.hint_text)
end

function TouchProbe:saveSwitchXYSetting(need_to_switch_xy)
    -- save the settings here so device.input can pick it up
    G_reader_settings:saveSetting("kobo_touch_switch_xy", need_to_switch_xy)
    G_reader_settings:flush()
    UIManager:quit()
end

function TouchProbe:onTapProbe(arg, ges)
    if self.curr_probe_step == 1 then
        local shorter_edge = math.min(Screen:getHeight(), Screen:getWidth())
        if math.min(ges.pos.x, ges.pos.y) < shorter_edge/2 then
            -- x mirrored, x should be close to zero and y should be close to
            -- screen height
            local need_to_switch_xy = ges.pos.x > ges.pos.y
            self:saveSwitchXYSetting(need_to_switch_xy)
        else
            -- x not mirrored, need one more probe
            self.curr_probe_step = 2
            self:updateProbeInstruction()
            UIManager:setDirty(self)
        end
    elseif self.curr_probe_step == 2 then
        -- x not mirrored, y should be close to zero and x should be close
        -- TouchProbe screen width
        local need_to_switch_xy = ges.pos.x < ges.pos.y
        self:saveSwitchXYSetting(need_to_switch_xy)
    end
end

return TouchProbe
