local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local ReaderStatus = WidgetContainer:extend{
    document = nil,
    enabled = true,
    total_pages = 0,
}

function ReaderStatus:init()
    if self.ui.document.is_pic then
        self.enabled = false
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
    local QuickStart = require("ui/quickstart")
    local last_file = G_reader_settings:readSetting("lastfile")
    if last_file == QuickStart.quickstart_filename then
        self:openFileBrowser()
        return
    end

    -- Should we start by marking the book as finished?
    if G_reader_settings:isTrue("end_document_auto_mark") then
        self:onMarkBook(true)
    end

    local next_file_enabled = G_reader_settings:readSetting("collate") ~= "access"
    local settings = G_reader_settings:readSetting("end_document_action")
    local top_widget = UIManager:getTopmostVisibleWidget() or {}
    if (settings == "pop-up" or settings == nil) and top_widget.name ~= "end_document" then
        local button_dialog
        local buttons = {
            {
                {
                    text_func = function()
                        return self.summary.status == "complete" and _("Mark as reading") or _("Mark as finished")
                    end,
                    callback = function()
                        self:onMarkBook()
                        UIManager:close(button_dialog)
                    end,
                },
                {
                    text = _("Book status"),
                    callback = function()
                        self:onShowBookStatus()
                        UIManager:close(button_dialog)
                    end,
                },

            },
            {
                {
                    text = _("Go to beginning"),
                    callback = function()
                        self.ui:handleEvent(Event:new("GoToBeginning"))
                        UIManager:close(button_dialog)
                    end,
                },
                {
                    text = _("Open next file"),
                    enabled = next_file_enabled,
                    callback = function()
                        self:onOpenNextDocumentInFolder()
                        UIManager:close(button_dialog)
                    end,
                },
            },
            {
                {
                    text = _("Delete file"),
                    callback = function()
                        self:deleteFile()
                        UIManager:close(button_dialog)
                    end,
                },
                {
                    text = _("File browser"),
                    callback = function()
                        self:openFileBrowser()
                        UIManager:close(button_dialog)
                    end,
                },
            },
        }
        button_dialog = ButtonDialogTitle:new{
            name = "end_document",
            title = _("You've reached the end of the document.\nWhat would you like to do?"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(button_dialog)
    elseif settings == "book_status" then
        self:onShowBookStatus()
    elseif settings == "next_file" then
        if next_file_enabled then
            local info = InfoMessage:new{
                text = _("Searching next file…"),
            }
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)
            -- Delay until the next tick, as this will destroy the Document instance,
            -- but we may not be the final Event caught by said Document...
            UIManager:nextTick(function()
                self:onOpenNextDocumentInFolder()
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
            text = _("You've reached the end of the document.\nThe current book is marked as finished."),
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
            self:deleteFile()
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

function ReaderStatus:onOpenNextDocumentInFolder()
    local FileManager = require("apps/filemanager/filemanager")
    if not FileManager.instance then
        self.ui:showFileManager()
    end
    local next_file = FileManager.instance.file_chooser:getNextFile(self.document.file)
    FileManager.instance:onClose()
    if next_file then
        self.ui:switchDocument(next_file)
    else
        UIManager:show(InfoMessage:new{
            text = _("This is the last file in the current folder. No next file to open."),
        })
    end
end

function ReaderStatus:deleteFile()
    self.settings:flush() -- enable additional warning text for newly opened file
    local FileManager = require("apps/filemanager/filemanager")
    local function pre_delete_callback()
        self.ui:onClose()
    end
    local function post_delete_callback()
        local path = util.splitFilePathName(self.document.file)
        FileManager:showFiles(path)
    end
    FileManager:showDeleteFileDialog(self.document.file, post_delete_callback, pre_delete_callback)
end

function ReaderStatus:onShowBookStatus(before_show_callback)
    local status_page = BookStatusWidget:new {
        thumbnail = FileManagerBookInfo:getCoverImage(self.document),
        props = self.document:getProps(),
        document = self.document,
        settings = self.settings,
        ui = self.ui,
    }
    if before_show_callback then
        before_show_callback()
    end
    status_page.dithered = true
    UIManager:show(status_page, "full")
    return true
end

-- If mark_read is true then we change status only from reading/abandoned to complete.
-- Otherwise we change status from reading/abandoned to complete or from complete to reading.
function ReaderStatus:onMarkBook(mark_read)
    self.summary.status = (not mark_read and self.summary.status == "complete") and "reading" or "complete"
    -- If History is called over Reader, it will read the file to get the book status, so save and flush
    self.settings:saveSetting("summary", self.summary)
    self.settings:flush()
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
    self.summary = config:readSetting("summary") or {}
end

return ReaderStatus
