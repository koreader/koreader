local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
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
    end
end

function ReaderStatus:addToMainMenu(menu_items)
    menu_items.book_status = {
        text = _("Book status"),
        callback = function()
            self:onShowBookStatus()
        end,
    }
end

function ReaderStatus:onEndOfBook()
    local settings = G_reader_settings:readSetting("end_document_action")
    local choose_action
    local collate = true
    local QuickStart = require("ui/quickstart")
    local last_file = G_reader_settings:readSetting("lastfile")
    if last_file and last_file == QuickStart.quickstart_filename then
        self:openFileBrowser()
        return
    end
    if G_reader_settings:readSetting("collate") == "access" then
        collate = false
    end
    if settings == "pop-up" or settings == nil then
        local buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(choose_action)
                    end,
                },
                {
                    text = _("Book status"),
                    callback = function()
                        self:onShowBookStatus()
                        UIManager:close(choose_action)
                    end,
                },

            },
            {
                {
                    text = _("Open next file"),
                    enabled = collate,
                    callback = function()
                        self:openNextFile(self.document.file)
                        UIManager:close(choose_action)
                    end,
                },
                {
                    text = _("File browser"),
                    callback = function()
                        self:openFileBrowser()
                        UIManager:close(choose_action)
                    end,
                },
            },
        }
        choose_action = ButtonDialogTitle:new{
            title = _("You've reached the end of the document.\nWhat would you like to do?"),
            title_align = "center",
            buttons = buttons,
        }

        UIManager:show(choose_action)
    elseif settings == "book_status" then
        self:onShowBookStatus()
    elseif settings == "next_file" then
        if G_reader_settings:readSetting("collate") ~= "access" then
            local info = InfoMessage:new{
                text = _("Searching next file…"),
            }
            UIManager:show(info)
            UIManager:forceRePaint()
            self:openNextFile(self.document.file)
            UIManager:close(info)
        else
            UIManager:show(InfoMessage:new{
                text = _("Could not open next file. Sort by last read date does not support this feature."),
            })
        end
    elseif settings == "file_browser" then
        self:openFileBrowser()
    elseif settings == "book_status_file_browser" then
        local before_show_callback = function() self:openFileBrowser() end
        self:onShowBookStatus(before_show_callback)
    end
end

function ReaderStatus:openFileBrowser()
    local FileManager = require("apps/filemanager/filemanager")
    if not FileManager.instance then
        self.ui:showFileManager()
    end
    self.ui:onClose()
    self.document = nil
end

function ReaderStatus:openNextFile(next_file)
    local FileManager = require("apps/filemanager/filemanager")
    if not FileManager.instance then
        self.ui:showFileManager()
    end
    next_file = FileManager.instance.file_chooser:getNextFile(next_file)
    FileManager.instance:onClose()
    if next_file then
        self.ui:switchDocument(next_file)
    else
        UIManager:show(InfoMessage:new{
            text = _("This is the last file in the current folder. No next file to open."),
        })
    end
end

function ReaderStatus:onShowBookStatus(before_show_callback)
    local status_page = BookStatusWidget:new {
        thumbnail = self.document:getCoverPageImage(),
        props = self.document:getProps(),
        document = self.document,
        settings = self.settings,
        view = self.view,
    }
    if before_show_callback then
        before_show_callback()
    end
    status_page.dithered = true
    UIManager:show(status_page, "full")
    return true
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
end

return ReaderStatus
