local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local OPDSBrowser = require("ui/widget/opdsbrowser")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local logger = require("logger")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local ReaderUI = require("apps/reader/readerui")
local ConfirmBox = require("ui/widget/confirmbox")
local T = require("ffi/util").template

local OPDSCatalog = InputContainer:extend{
    title = _("OPDS Catalog"),
    opds_servers = {
        {
            title = "Project Gutenberg",
            subtitle = "Free ebooks since 1971.",
            url = "http://m.gutenberg.org/ebooks.opds/?format=opds",
        },
        {
            title = "Feedbooks",
            subtitle = "",
            url = "http://www.feedbooks.com/publicdomain/catalog.atom",
        },
        {
            title = "ManyBooks",
            subtitle = "Online Catalog for Manybooks.net",
            url = "http://manybooks.net/opds/index.php",
        },
        {
            title = "Internet Archive",
            subtitle = "Internet Archive Catalog",
            url = "http://bookserver.archive.org/catalog/",
        },
    },
    onExit = function() end,
}

function OPDSCatalog:init()
    local opds_browser = OPDSBrowser:new{
        opds_servers = self.opds_servers,
        title = self.title,
        show_parent = self,
        is_popout = false,
        is_borderless = true,
        has_close_button = true,
        close_callback = function() return self:onClose() end,
        file_downloaded_callback = function(downloaded_file)
            UIManager:show(ConfirmBox:new{
                text = T(_("File saved to:\n %1\nWould you like to read the downloaded book now?"),
                    downloaded_file),
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
