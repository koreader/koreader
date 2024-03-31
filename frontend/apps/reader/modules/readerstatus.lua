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
        -- Like onOpenNextDocumentInFolder, delay this so as not to break instance lifecycle
        UIManager:nextTick(function()
            self:openFileBrowser()
        end)
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
                        UIManager:close(button_dialog)
                        self:onMarkBook()
                    end,
                },
                {
                    text = _("Book status"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onShowBookStatus()
                    end,
                },

            },
            {
                {
                    text = _("Go to beginning"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self.ui:handleEvent(Event:new("GoToBeginning"))
                    end,
                },
                {
                    text = _("Open next file"),
                    enabled = next_file_enabled,
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onOpenNextDocumentInFolder()
                    end,
                },
            },
            {
                {
                    text = _("Delete file"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:deleteFile()
                    end,
                },
                {
                    text = _("File browser"),
                    callback = function()
                        UIManager:close(button_dialog)
                        -- Ditto
                        UIManager:nextTick(function()
                            self:openFileBrowser()
                        end)
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
            self:onOpenNextDocumentInFolder()
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
    local FileChooser = require("ui/widget/filechooser")
    local next_file = FileChooser:getNextFile(self.document.file)
    if next_file then
        -- Delay until the next tick, as this will destroy the Document instance,
        -- but we may not be the final Event caught by said Document...
        UIManager:nextTick(function()
            self.ui:switchDocument(next_file)
        end)
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
        props = self.ui.doc_props,
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
    self.summary.modified = os.date("%Y-%m-%d", os.time())
    -- If History is called over Reader, it will read the file to get the book status, so save and flush
    self.settings:saveSetting("summary", self.summary)
    self.settings:flush()
end

function ReaderStatus:onReadSettings(config)
    self.settings = config
    self.summary = config:readSetting("summary") or {}
end

return ReaderStatus
