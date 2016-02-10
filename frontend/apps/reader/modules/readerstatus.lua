local InputContainer = require("ui/widget/container/inputcontainer")
local StatusWidget = require("ui/widget/statuswidget")

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
    if self.ui.document.is_djvu or self.ui.document.is_pdf or self.ui.document.is_pic then
        self.enabled = false
        return
    end
    self.total_pages = self.document:getPageCount()
    UIManager:scheduleIn(0.1, function() self.ui.menu:registerToMainMenu(self) end)
end

function ReaderStatus:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.typeset, {
        text = _("Status"),
        callback = function()
            self:showStatus()
            UIManager:setDirty("all")
        end,
    })
end

function ReaderStatus:showStatus()
    local statusWidget = StatusWidget:new {
        thumbnail = self.document:getCoverPageImage(),
        props = self.document:getProps(),
        document = self.document,
        settings = self.settings,
    }
    UIManager:show(statusWidget)
end

function ReaderStatus:onPageUpdate(pageno)
    if self.enabled then
        --in case when pageUpdate event generated before _document:render()
        if pageno > self.total_pages or self.total_pages == 1 then
            self.total_pages = self.document:getPageCount()
        end

        if pageno == self.total_pages and self.total_pages ~= 1 then
            self:showStatus()
        end
    end
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
end

return ReaderStatus

