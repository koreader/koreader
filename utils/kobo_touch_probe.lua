-- touch probe utility
-- usage: ./luajit util/kobo_touch_probe.lua

require "defaults"
package.path = "common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" .. package.path
package.cpath = "common/?.so;common/?.dll;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" .. package.cpath

local DocSettings = require("docsettings")
local _ = require("gettext")

-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = DocSettings:open(".reader")
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = require("device").screen
local Input = require("device").input
local Font = require("ui/font")
local DEBUG = require("dbg")
--DEBUG:turnOn()

local TouchProbe = InputContainer:new{
}

function TouchProbe:init()
    self.ges_events = {
        TapProbe = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            }
        },
    }
    local image_widget = ImageWidget:new{
        file = "resources/kobo-touch-probe.png",
    }
    self[1] = OverlapGroup:new{
        dimen = Screen:getSize(),
        CenterContainer:new{
            dimen = Screen:getSize(),
            TextWidget:new{
                text = _("Tap the upper right corner"),
                face = Font:getFace("cfont", 30),
            },
        },
        RightContainer:new{
            dimen = {
                h = image_widget:getSize().h,
                w = Screen:getSize().w,
            },
            image_widget,
        },
    }
end

function TouchProbe:onTapProbe(arg, ges)
    --DEBUG("onTapProbe", ges)
    local need_to_switch_xy = ges.pos.x < ges.pos.y
    --DEBUG("Need to switch xy", need_to_switch_xy)
    G_reader_settings:saveSetting("kobo_touch_switch_xy", need_to_switch_xy)
    G_reader_settings:close()
    if need_to_switch_xy then
        Input:registerEventAdjustHook(Input.adjustTouchSwitchXY)
    end
    UIManager:quit()
end

-- if user has not set KOBO_TOUCH_MIRRORED yet
if KOBO_TOUCH_MIRRORED == nil then
    local switch_xy = G_reader_settings:readSetting("kobo_touch_switch_xy")
    -- and has no probe before
    if switch_xy == nil then
        UIManager:show(TouchProbe:new{})
        UIManager:run()
    -- otherwise, we will use probed result
    else
        KOBO_TOUCH_MIRRORED = switch_xy
    end
end
