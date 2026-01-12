local BookStatusWidget = require("ui/widget/bookstatuswidget")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local ReaderStatus = WidgetContainer:extend{
}

function ReaderStatus:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderStatus:addToMainMenu(menu_items)
    menu_items.book_status = {
        text = _("Book status"),
        callback = function()
            self:onShowBookStatus()
        end,
    }
end

function ReaderStatus:onShowBookStatus(close_callback)
    local status_page = BookStatusWidget:new{
        ui = self.ui,
        close_callback = close_callback,
    }
    UIManager:show(status_page, "full")
    return true
end

-- End of book

function ReaderStatus:onEndOfBook()
    Device:performHapticFeedback("CONTEXT_CLICK")
    local QuickStart = require("ui/quickstart")
    local last_file = G_reader_settings:readSetting("lastfile")
    if last_file == QuickStart.quickstart_filename then
        -- Like onOpenNextOrPreviousFileInFolder, delay this so as not to break instance lifecycle
        UIManager:nextTick(function()
            self:openFileBrowser()
        end)
        return
    end

    -- Should we start by marking the book as finished?
    if G_reader_settings:isTrue("end_document_auto_mark") then
        self:markBook(true)
    end

    local collate = G_reader_settings:readSetting("collate")
    local next_file_enabled = collate ~= "access" and collate ~= "date"
    local settings = G_reader_settings:readSetting("end_document_action") or "pop-up"
    local top_widget = UIManager:getTopmostVisibleWidget() or {}
    if settings == "pop-up" and top_widget.name ~= "end_document" then
        local button_dialog
        local buttons = {
            {
                {
                    text_func = function()
                        local status = self.ui.doc_settings:readSetting("summary").status
                        return status == "complete" and _("Mark as reading") or _("Mark as finished")
                    end,
                    callback = function()
                        UIManager:close(button_dialog)
                        self:markBook()
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
                        self.ui.gotopage:onGoToBeginning()
                    end,
                },
                {
                    text = _("Open next file"),
                    enabled = next_file_enabled,
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onOpenNextOrPreviousFileInFolder()
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
        button_dialog = ButtonDialog:new{
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
            self:onOpenNextOrPreviousFileInFolder()
        else
            UIManager:show(InfoMessage:new{
                text = _("Could not open next file. Sort by date does not support this feature."),
            })
        end
    elseif settings == "goto_beginning" then
        self.ui.gotopage:onGoToBeginning()
    elseif settings == "file_browser" then
        -- Ditto
        UIManager:nextTick(function()
            self:openFileBrowser()
        end)
    elseif settings == "mark_read" then
        self:markBook(true)
        UIManager:show(InfoMessage:new{
            text = _("You've reached the end of the document.\nThe current book is marked as finished."),
            timeout = 3
        })
    elseif settings == "book_status_file_browser" then
        -- Ditto
        UIManager:nextTick(function()
            local book_status_close_callback = function() self:openFileBrowser() end
            self:onShowBookStatus(book_status_close_callback)
        end)
    elseif settings == "delete_file" then
        -- Ditto
        UIManager:nextTick(function()
            self:deleteFile()
        end)
    end
end

function ReaderStatus:openFileBrowser()
    local file = self.document.file
    self.ui:onClose()
    self.ui:showFileManager(file)
end

function ReaderStatus:onOpenNextOrPreviousFileInFolder(prev)
    local collate = G_reader_settings:readSetting("collate")
    if collate == "access" or collate == "date" then return true end
    local FileChooser = require("ui/widget/filechooser")
    local fc = FileChooser:new{ ui = self.ui }
    local file = fc:getNextOrPreviousFileInFolder(self.document.file, prev)
    if file then
        -- Delay until the next tick, as this will destroy the Document instance,
        -- but we may not be the final Event caught by said Document...
        UIManager:nextTick(function()
            self.ui:switchDocument(file)
        end)
    else
        UIManager:show(InfoMessage:new{
            text = prev and _("This is the first file in the folder. No previous file to open.")
                         or _("This is the last file in the folder. No next file to open."),
        })
    end
    return true
end

function ReaderStatus:deleteFile()
    self.ui.doc_settings:flush() -- enable additional warning text for newly opened file
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

-- If mark_read is true then we change status only from reading/abandoned to complete.
-- Otherwise we change status from reading/abandoned to complete or from complete to reading.
function ReaderStatus:markBook(mark_read)
    local summary = self.ui.doc_settings:readSetting("summary")
    summary.status = (not mark_read and summary.status == "complete") and "reading" or "complete"
    summary.modified = os.date("%Y-%m-%d", os.time())
    -- If History is called over Reader, it will read the file to get the book status, so flush
    self.ui.doc_settings:flush()
end

return ReaderStatus
