local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local OPDSBrowser = require("ui/widget/opdsbrowser")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local OPDSCatalog = InputContainer:extend{
    title = _("OPDS Catalog"),
    onExit = function() end,
}

function OPDSCatalog:init()
    local opds_browser = OPDSBrowser:new{
        title = self.title,
        show_parent = self,
        is_popout = false,
        is_borderless = true,
        has_close_button = true,
        close_callback = function() return self:onClose() end,
        file_downloaded_callback = function(downloaded_file)
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"),
                    BD.filepath(downloaded_file)),
                ok_text = _("Read now"),
                cancel_text = _("Read later"),
                ok_callback = function()
                    self:onClose()
                    ReaderUI:showReader(downloaded_file)
                end
            })
        end,
    }

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        opds_browser,
    }
end

function OPDSCatalog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1].dimen
    end)
end

function OPDSCatalog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "partial", self[1].dimen
    end)
end

function OPDSCatalog:showCatalog()
    logger.dbg("show OPDS catalog")
    UIManager:show(OPDSCatalog:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        onExit = function()
            --UIManager:quit()
        end
    })
end

function OPDSCatalog:onClose()
    logger.dbg("close OPDS catalog")
    UIManager:close(self)
    if self.onExit then
        self:onExit()
    end
    return true
end

return OPDSCatalog
