local BD = require("ui/bidi")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

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
    Device:performHapticFeedback("CONTEXT_CLICK")
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

    -- Should we start by marking the book as read?
    if G_reader_settings:isTrue("end_document_auto_mark") then
        self:onMarkBook(true)
    end

    if (settings == "pop-up" or settings == nil) and UIManager:getTopWidget() ~= "end_document" then
        local buttons = {
            {
                {
                    text_func = function()
                        if self.settings.data.summary and self.settings.data.summary.status == "complete" then
                            return _("Mark as reading")
                        else
                            return _("Mark as read")
                        end
                    end,
                    callback = function()
                        self:onMarkBook()
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
                    text = _("Go to beginning"),
                    callback = function()
                        self.ui:handleEvent(Event:new("GoToBeginning"))
                        UIManager:close(choose_action)
                    end,
                },
                {
                    text = _("Open next file"),
                    enabled = collate,
                    callback = function()
                        self:openNextFile(self.document.file)
                        UIManager:close(choose_action)
                    end,
                },
            },
            {
                {
                    text = _("Delete file"),
                    callback = function()
                        self:deleteFile(self.document.file, false)
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
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(choose_action)
                    end,
                },
            },
        }
        choose_action = ButtonDialogTitle:new{
            name = "end_document",
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
            UIManager:close(info)
            -- Delay until the next tick, as this will destroy the Document instance, but we may not be the final Event caught by said Document...
            UIManager:nextTick(function()
                self:openNextFile(self.document.file)
            end)
        else
            UIManager:show(InfoMessage:new{
                text = _("Could not open next file. Sort by last read date does not support this feature."),
            })
        end
    elseif settings == "goto_beginning" then
        self.ui:handleEvent(Event:new("GoToBeginning"))
    elseif settings == "file_browser" then
        -- Ditto
        UIManager:nextTick(function()
            self:openFileBrowser()
        end)
    elseif settings == "mark_read" then
        self:onMarkBook(true)
        UIManager:show(InfoMessage:new{
            text = _("You've reached the end of the document.\nThe current book is marked as read."),
            timeout = 3
        })
    elseif settings == "book_status_file_browser" then
        -- Ditto
        UIManager:nextTick(function()
            local before_show_callback = function() self:openFileBrowser() end
            self:onShowBookStatus(before_show_callback)
        end)
    elseif settings == "delete_file" then
        -- Ditto
        UIManager:nextTick(function()
            self:deleteFile(self.document.file, true)
        end)
    end
end

function ReaderStatus:openFileBrowser()
    local FileManager = require("apps/filemanager/filemanager")
    self.ui:onClose()
    if not FileManager.instance then
        self.ui:showFileManager()
    end
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

function ReaderStatus:deleteFile(file, text_end_book)
    local ConfirmBox = require("ui/widget/confirmbox")
    local message_end_book = ""
    if text_end_book then
        message_end_book = "You've reached the end of the document.\n"
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("%1Are you sure that you want to delete this file?\n%2\nIf you delete a file, it is permanently lost."), message_end_book, BD.filepath(file)),
        ok_text = _("Delete"),
        ok_callback = function()
            local FileManager = require("apps/filemanager/filemanager")
            self.ui:onClose()
            FileManager:deleteFile(file)
            require("readhistory"):fileDeleted(file) -- (will update "lastfile")
            if FileManager.instance then
                FileManager.instance.file_chooser:refreshPath()
            else
                FileManager:showFiles()
            end
        end,
    })
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

-- If mark_read is true then we change status only from reading/abandoned to read (complete).
-- Otherwise we change status from reading/abandoned to read or from read to reading.
function ReaderStatus:onMarkBook(mark_read)
    if self.settings.data.summary and self.settings.data.summary.status then
        local current_status = self.settings.data.summary.status
        if current_status == "complete" then
            if mark_read then
                -- Keep mark as read.
                self.settings.data.summary.status = "complete"
            else
                -- Change current status from read (complete) to reading
                self.settings.data.summary.status = "reading"
            end
        else
            self.settings.data.summary.status = "complete"
        end
    else
        self.settings.data.summary = {status = "complete"}
    end
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
end

return ReaderStatus
