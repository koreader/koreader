local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local KoboBrowser = require("kobobrowser")
local KoboApi = require "core/koboapi"
local KoboDb = require "core/kobodb"
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = require("device").screen

local KoboCatalog = WidgetContainer:extend{
}

function KoboCatalog:init()
    KoboDb:openDb()
    KoboApi:setApiSettings(KoboDb:loadApiSettings())

    local kobo_browser = KoboBrowser:new{
        title = _("Kobo books"),
        show_parent = self,
        is_popout = false,
        is_borderless = true,
        is_enable_shortcut = false,
        close_callback = function() return self:onClose() end,
    }

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        kobo_browser,
    }
end

function KoboCatalog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1].dimen -- i.e., FrameContainer
    end)
end

function KoboCatalog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1].dimen
    end)
end

function KoboCatalog:showCatalog()
    UIManager:show(KoboCatalog:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
    })
end

function KoboCatalog:onClose()
	KoboDb:saveApiSettings(KoboApi:getApiSettings())
    KoboDb:closeDb()

    UIManager:close(self)
    return true
end

return KoboCatalog
