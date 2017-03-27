local InputContainer = require("ui/widget/container/inputcontainer")
local BookStatusWidget = require("ui/widget/bookstatuswidget")

local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ReaderStatus = InputContainer:new {
    document = nil,
    summary = {
        rating = 0,
        note = nil,
        status = "",
        modified = "",
    },
    enabled = true,
    total_pages = 0
}

function ReaderStatus:init()
    if self.ui.document.is_pic then
        self.enabled = false
        return
    else
        self.total_pages = self.document:getPageCount()
        self.ui.menu:registerToMainMenu(self)
        -- register event listener if enabled
        if G_reader_settings:nilOrTrue("auto_book_status") then
            self.onEndOfBook = function()
                self:showStatus()
            end
        end
    end
end

function ReaderStatus:addToMainMenu(menu_items)
    menu_items.book_status = {
        text = _("Book status"),
        callback = function()
            self:showStatus()
        end,
    }
end

function ReaderStatus:showStatus()
    local status_page = BookStatusWidget:new {
        thumbnail = self.document:getCoverPageImage(),
        props = self.document:getProps(),
        document = self.document,
        settings = self.settings,
        view = self.view,
    }
    UIManager:show(status_page)
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
end

return ReaderStatus
