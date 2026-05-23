local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local BookMetadataArchive = WidgetContainer:extend{
}

function BookMetadataArchive:showBookList(ui)
    self.ui = ui or require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    self.books = self.getBookList()
    self.book_list = BookList:new{
        onMenuSelect = function(self_menu, item)
            self:showBookDialog(item)
        end,
        close_callback = function()
            self.books = nil
            self.book_list = nil
            UIManager:scheduleIn(0.5, function()
                collectgarbage()
                collectgarbage()
            end)
        end,
    }
    self:updateBookList()
    UIManager:show(self.book_list)
end

function BookMetadataArchive:updateBookList()
    local title = _("Book metadata archive") .. " (" .. #self.books .. ")"
    self.book_list:switchItemTable(title, self.books, -1)
end

function BookMetadataArchive.getBookList()
    local book_list = {}
    util.findFiles(G_reader_settings:readSetting("document_metadata_arc_folder"), function(fullpath, filename)
        if filename:match("%.lua$") then
            local doc_settings = LuaSettings:open(fullpath)
            if doc_settings:has("metadata_arc") then
                table.insert(book_list, BookMetadataArchive.buildItem(doc_settings))
            end
        end
    end, false)
    if #book_list > 1 then
        table.sort(book_list, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    end
    return book_list
end

function BookMetadataArchive.buildItem(doc_settings)
    local doc_props = doc_settings:readSetting("doc_props")
    local metadata_arc = doc_settings:readSetting("metadata_arc")
    if metadata_arc.custom_props then
        for prop_key, prop_value in pairs(metadata_arc.custom_props) do
            doc_props[prop_key] = prop_value
        end
    end
    doc_props.display_title = doc_props.title
        or filemanagerutil.splitFileNameType(doc_settings:readSetting("doc_path"))
    local authors = doc_props.authors and doc_props.authors:gsub("\n.*", " et al.") or _("Unknown author")
    return {
        text = T(_("%1 • %2"), authors, doc_props.display_title),
        mandatory = BookMetadataArchive.getItemMandatory(doc_settings),
        doc_settings = doc_settings,
    }
end

function BookMetadataArchive.getItemMandatory(doc_settings)
    local metadata_arc = doc_settings:readSetting("metadata_arc")
    local t = {}
    if metadata_arc.on_closing then
        table.insert(t, "\u{e28b}") -- book
    end
    if #doc_settings:readSetting("annotations") > 0 then
        table.insert(t, "\u{2592}") -- medium shade
    end
    table.insert(t, metadata_arc.datetime:sub(1, 10)) -- date
    return table.concat(t, " ")
end

function BookMetadataArchive:showBookDialog(item)
    local doc_settings = item.doc_settings
    local metadata_arc = doc_settings:readSetting("metadata_arc")
    local arc_file = DocSettings.getSettingsArcFile(doc_settings:readSetting("partial_md5_checksum"))
    local book_deleted_button_text = _("Book deleted")
    if not metadata_arc.on_closing then
        book_deleted_button_text = book_deleted_button_text .. " \u{2713}" -- checkmark
    end

    local book_dialog
    local function close_dialog_callback()
        UIManager:close(book_dialog)
    end
    local buttons = {
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete metadata from archive?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            UIManager:close(book_dialog)
                            os.remove(arc_file)
                            os.remove(arc_file .. ".old")
                            table.remove(self.books, item.idx)
                            self:updateBookList()
                        end,
                    })
                end,
            },
            self.ui.collections:genBookmarkBrowserButton({ [arc_file] = true }, close_dialog_callback,
                #doc_settings:readSetting("annotations") == 0),
        },
        {
            {
                text = book_deleted_button_text,
                enabled = metadata_arc.on_closing or false,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Mark book as deleted?"),
                        ok_text = _("Mark"),
                        ok_callback = function()
                            UIManager:close(book_dialog)
                            metadata_arc.on_closing = nil
                            doc_settings:flush()
                            self.books[item.idx].mandatory = BookMetadataArchive.getItemMandatory(doc_settings)
                            self.book_list:updateItems(1, true)
                        end,
                    })
                end,
            },
            filemanagerutil.genBookInformationButton(doc_settings, doc_settings:readSetting("doc_props"), close_dialog_callback),
        },
    }
    book_dialog = ButtonDialog:new{
        title = item.text:gsub(" • ", "\n"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(book_dialog)
end

return BookMetadataArchive
