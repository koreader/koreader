local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local DocumentRegistry = require("document/documentregistry")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonDialog = require("ui/widget/buttondialog")
local VerticalSpan = require("ui/widget/verticalspan")
local OPDSBrowser = require("ui/widget/opdsbrowser")
local TextWidget = require("ui/widget/textwidget")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")
local util = require("ffi/util")
local Blitbuffer = require("ffi/blitbuffer")

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
            baseurl = "http://bookserver.archive.org/catalog/",
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
    }

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        opds_browser,
    }

end

function OPDSCatalog:showCatalog()
    DEBUG("show OPDS catalog")
    UIManager:show(OPDSCatalog:new{
        dimen = Screen:getSize(),
        onExit = function()
            --UIManager:quit()
        end
    })
end

function OPDSCatalog:onClose()
    DEBUG("close OPDS catalog")
    UIManager:close(self)
    if self.onExit then
        self:onExit()
    end
    return true
end

return OPDSCatalog
