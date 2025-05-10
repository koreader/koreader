local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local ffiUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KoboApi = require "core/koboapi"
local KoboDb = require "core/kobodb"
local KoboDrm = require "core/kobodrm"
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Menu = require("ui/widget/menu")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")

local function formatBookTitle(title, author)
    if #author > 0 then
        return author .. ": " .. title
    else
        return title
    end
end

-- date: input date in a format like this: 2024-08-11T18:58:16.7429913Z
local function formatDate(date)
    -- TODO: Kobo: input is UTC, output should be local. Use newsdownloader.koplugin/lib/dateparser?
    local year, month, day = date:match("(%d+)-(%d+)-(%d+)T")
    return string.format("%s-%s-%s", year, month, day)
end

-- The go to parent button is disabled if there are no items, so we always add at least one.
local function extendEmptyItems(items)
    if #items > 0 then
        return items
    else
        table.insert(items, {text = "No items"})
        return items
    end
end

local function loadBooks(include_read, include_unread, include_archived)
    local books = KoboDb:getBooks(include_read, include_unread, include_archived)

    local table_items = {}
    for _, book in ipairs(books) do
        local table_item = {
            text = formatBookTitle(book.title, book.author),
            type = "book",
            entitlement_id = book.entitlement_id,
        }
        table.insert(table_items, table_item)
    end

    table.sort(table_items, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    return table_items
end

local function loadWishlist()
    local items = KoboDb:getWishlist()

    local table_items = {}
    for i, item in ipairs(items) do
        local table_item = {
            text = formatBookTitle(item.title, item.author),
            type = "wishlist_item",
            cross_revision_id = item.cross_revision_id,
        }
        table.insert(table_items, table_item)
    end

    table.sort(table_items, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    return table_items
end

local function formatBookInformationDialogText(title, book_info)
    local book_info_text = book_info.title

    if #book_info.author > 0 then
        book_info_text = book_info_text .. "\nby " .. book_info.author
    end
    if #book_info.series_name > 0 then
        if #book_info.series_number > 0 then
            book_info_text = book_info_text .. string.format("\nBook %s - %s", book_info.series_number, book_info.series_name)
        else
            book_info_text = book_info_text .. "\n" .. book_info.series_name
        end
    end
    if #book_info.description > 0 then
        book_info_text = book_info_text .. "\n\nDescription:\n"
        book_info_text = book_info_text .. util.htmlToPlainTextIfHtml(book_info.description) .. "\n"
    end
    if #book_info.isbn > 0 then
        book_info_text = book_info_text .. "\nISBN: " .. book_info.isbn
    end
    if #book_info.language > 0 then
        book_info_text = book_info_text .. "\nLanguage: " .. book_info.language
    end
    if #book_info.publication_date > 0 then
        book_info_text = book_info_text .. "\nPublication date: " .. formatDate(book_info.publication_date)
    end
    if #book_info.publisher_name > 0 then
        book_info_text = book_info_text .. "\nPublisher: " .. book_info.publisher_name
    end
    if #book_info.publisher_imprint > 0 then
        book_info_text = book_info_text .. "\nPublisher imprint: " .. book_info.publisher_imprint
    end
    if book_info.read ~= 0 then
        if #book_info.last_time_finished_reading > 0 then
            book_info_text = book_info_text .. string.format("\nRead date: %s", formatDate(book_info.last_time_finished_reading))
        else
            book_info_text = book_info_text .. "\nRead"
        end
    end
    if #book_info.date_added_to_wishlist > 0 then
        book_info_text = book_info_text .. string.format("\nWishlisting date: %s", formatDate(book_info.date_added_to_wishlist))
    end

    return book_info_text
end

local menu_items = {
    {text = "Unread books", type = "unread_books"},
    {text = "Read books", type = "read_books"},
    {text = "All books", type = "all_books"},
    {text = "Wishlist", type = "wishlist"},
    {text = "Archived books", type = "archived_books"},
    {text = "", type = ""},
    {text = "Synchronize", type = "synchronize"},
}

local KoboBrowser = Menu:extend{
    downloaded_a_book = false,
}

function KoboBrowser:init()
    self.item_table = menu_items
    Menu.init(self) -- call parent's init()
end

function KoboBrowser:onClose()
    if self.downloaded_a_book then
        self.downloaded_a_book = false
        -- Refresh the file manager if it is open.
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then
            FileManager.instance:onRefresh()
        end
    end

    return Menu.onClose(self)
end

function KoboBrowser:openBookList(title, include_read, include_unread)
    local books = loadBooks(include_read, include_unread, false)
    title = string.format("%s (%d)", title, #books)
    self.paths = {true}
    self:switchItemTable(title, extendEmptyItems(books))
end

function KoboBrowser:openWishlist()
    local wishlist = loadWishlist()
    local title = string.format("Wishlist (%d)", #wishlist)
    self.paths = {true}
    self:switchItemTable(title, extendEmptyItems(wishlist))
end

function KoboBrowser:openArchivedBooks()
    local archivedBooks = loadBooks(false, false, true)
    local title = string.format("Archived books (%d)", #archivedBooks)
    self.paths = {true}
    self:switchItemTable(title, extendEmptyItems(archivedBooks))
end

function KoboBrowser:loginWaitTillActivation(activation_check_url, finished_callback)
    local user_id, user_key = KoboApi:waitTillActivation(activation_check_url)
    if user_id == nil or user_key == nil then
        UIManager:show(InfoMessage:new{
            text = "Activation did not finish.",
            icon = "notice-warning",
        })
        finished_callback()
        return
    end

    if not KoboApi:authenticateDevice(user_id, user_key) then
        UIManager:show(InfoMessage:new{
            text = "Device authentication has failed.",
            icon = "notice-warning",
        })
    end

    finished_callback()
end

function KoboBrowser:login(finished_callback)
    local activation_check_url, activation_code = KoboApi:activateOnWeb()
    if activation_check_url == nil or activation_code == nil then
        UIManager:show(InfoMessage:new{
            text = "Failed to start web-based activation.",
            icon = "notice-warning",
        })
        finished_callback()
        return
    end

    local activation_message = T(_([[
The Kobo KOReader plugin uses the same web-based activation method to log in as the Kobo e-readers.
You will have to open the link below in your browser and enter the code, then you might need to login too if kobo.com asks you to.

Open
"https://www.kobo.com/activate"
and enter %1 as the code.

After finishing the activation on kobo.com press the I'm done with activation button below.
]]), activation_code)

    UIManager:show(ConfirmBox:new{
        text = activation_message,
        ok_text = _("I'm done with activation"),
        ok_callback = function()
            self:loginWaitTillActivation(activation_check_url, finished_callback)
        end,
        cancel_callback = function()
            finished_callback()
        end,
    })
end

function KoboBrowser:synchronizeBooksAndWishlistInternal()
    local library_sync_items = KoboApi:getLibrarySync()
    if library_sync_items == nil then
        UIManager:show(InfoMessage:new{
            text = "Failed get library state from Kobo.",
            icon = "notice-warning",
        })
    else
        KoboDb:applyLibrarySyncItems(library_sync_items)
    end

    local wishlist_items = KoboApi:getWishlist()
    if wishlist_items == nil then
        UIManager:show(InfoMessage:new{
            text = "Failed get wishlist from Kobo.",
            icon = "notice-warning",
        })
    else
        KoboDb:clearWishlist()
        KoboDb:refreshWishlist(wishlist_items)
    end
end

function KoboBrowser:synchronizeBooksAndWishlist()
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = _("Synchronizing…"),
            timeout = 1,
        })
    end)

    UIManager:tickAfterNext(function()
        self:synchronizeBooksAndWishlistInternal()
    end)
end

function KoboBrowser:loginAndSynchronizeBooksAndWishlist()
    if KoboApi:isLoggedIn() then
        self:synchronizeBooksAndWishlist()
    else
        local login_finished = function()
            if KoboApi:isLoggedIn() then
                KoboDb:saveApiSettings(KoboApi:getApiSettings())
                self:synchronizeBooksAndWishlist()
            end
        end
        self:login(login_finished)
    end
end

function KoboBrowser:onMenuSelect(item)
    if item.type == "unread_books" then
        self:openBookList("Unread books", false, true)
    elseif item.type == "read_books" then
        self:openBookList("Read books", true, false)
    elseif item.type == "all_books" then
        self:openBookList("All books", true, true)
    elseif item.type == "wishlist" then
        self:openWishlist()
    elseif item.type == "archived_books" then
        self:openArchivedBooks()
    elseif item.type == "synchronize" then
        self:loginAndSynchronizeBooksAndWishlist()
    elseif item.type == "book" or item.type == "wishlist_item" then
        self:showBookDialog(item)
    end
end

function KoboBrowser:onReturn()
    self.paths = {}
    self:switchItemTable("Kobo Catalog", menu_items)
end

function KoboBrowser.getCurrentDownloadDir()
    return G_reader_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
end

-- Downloads a book (with "File already exists" dialog)
function KoboBrowser:downloadBook(filename, remote_url)
    local download_dir = self.getCurrentDownloadDir()
    filename = util.getSafeFilename(filename, download_dir)
    local local_path = (download_dir ~= "/" and download_dir or "") .. '/' .. filename
    local_path = util.fixUtf8(local_path, "_")

    local function download()
        UIManager:show(InfoMessage:new{
            text = _("Downloading…"),
            timeout = 1,
        })

        -- This is needed otherwise the Downloading… InfoMessage does not appear.
        UIManager:nextTick(function()
            local succeeded, content_keys, code, headers, status = KoboApi:download(remote_url, local_path)
            if succeeded then
                logger.dbg("File downloaded to", local_path)
                self:onFileDownloaded(local_path, content_keys)
            else
                util.removeFile(local_path)
                logger.dbg("KoboBrowser:downloadBook: Request failed with HTTP response code: " .. code .. ". Status:", status)
                logger.dbg("KoboBrowser:downloadBook: Response headers:", headers)
                UIManager:show(InfoMessage:new {
                    text = T(_("Could not save file to:\n%1\n%2"),
                        BD.filepath(local_path),
                        status or code or "network unreachable"),
                })
            end
        end)
    end

    if lfs.attributes(local_path) then
        UIManager:show(ConfirmBox:new{
            text = T(_("The file %1 already exists. Do you want to overwrite it?"), BD.filepath(local_path)),
            ok_text = _("Overwrite"),
            ok_callback = function()
                download()
            end,
        })
    else
        download()
    end
end

function KoboBrowser:onFileDownloaded(file_path, content_keys)
    self.downloaded_a_book = true

    if content_keys ~= nil then
        logger.dbg("KoboBrowser:onFileDownloaded: removing DRM from", file_path)
        local api_settings = KoboApi:getApiSettings()
        local output_file_path = file_path .. ".tmp"
        if KoboDrm:removeKoboDrm(api_settings.device_id, api_settings.user_id, content_keys, file_path, output_file_path) then
            os.remove(file_path)
            os.rename(output_file_path, file_path)
        else
            UIManager:show(InfoMessage:new{
                text = "DRM removal has failed.",
                icon = "notice-warning",
            })

            return
        end
    end

    UIManager:show(ConfirmBox:new{
        text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(file_path)),
        ok_text = _("Read now"),
        cancel_text = _("Read later"),
        ok_callback = function()
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("SetupShowReader"))

            self:onClose()

            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(file_path)
        end,
    })
end

function KoboBrowser:showBookDialog(item)
    -- TODO: Kobo: use more complete description from https://storeapi.kobo.com/v1/products/books/{Id} instead?
    local book_info = nil
    if item.type == "book" then
        book_info = KoboDb:getBookInfo(item.entitlement_id)
    elseif item.type == "wishlist_item" then
        book_info = KoboDb:getWishlistItemInfo(item.cross_revision_id)
    else
        return -- type is checked on caller's side, so this is impossible
    end

    local filename = book_info.title
    if #book_info.author > 0 then
        filename = book_info.author .. " - " .. book_info.title
    end
    if item.type == "wishlist_item" then
        filename = filename .. " (sample)"
    end
    local filename_original = filename

    local function createTitle(path, file) -- title for ButtonDialog
        return T(_("Download folder:\n%1\n\nDownload filename:\n%2\n\nDownload file type:"), BD.dirpath(path), file)
    end

    local buttons = {} -- buttons for ButtonDialog
    local download_buttons = {} -- file type download buttons
    for _, download_info in ipairs(book_info.download_info_list) do
        table.insert(download_buttons, {
            text = download_info.display_format .. "\u{2B07}", -- append DOWNWARDS BLACK ARROW
            callback = function()
                self:downloadBook(filename .. "." .. download_info.file_extension, download_info.url)
                UIManager:close(self.download_dialog)
            end,
        })
    end

    local button_count = #download_buttons
    if button_count > 0 then
        if button_count == 1 then -- one wide button
            table.insert(buttons, download_buttons)
        else
            if button_count % 2 == 1 then -- we need even number of buttons
                table.insert(download_buttons, {text = ""})
            end
            for i = 1, button_count, 2 do -- two buttons in a row
                table.insert(buttons, {download_buttons[i], download_buttons[i+1]})
            end
        end
        table.insert(buttons, {}) -- separator
    end

    if #book_info.download_info_list > 0 then
        table.insert(buttons, { -- action buttons
            {
                text = _("Choose folder"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        onConfirm = function(path)
                            logger.dbg("Download folder set to", path)
                            G_reader_settings:saveSetting("download_dir", path)
                            self.download_dialog:setTitle(createTitle(path, filename))
                        end,
                    }:chooseDir(self.getCurrentDownloadDir())
                end,
            },
            {
                text = _("Change filename"),
                callback = function()
                    local dialog
                    dialog = InputDialog:new{
                        title = _("Enter filename"),
                        input = filename or filename_original,
                        input_hint = filename_original,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                    end,
                                },
                                {
                                    text = _("Set filename"),
                                    is_enter_default = true,
                                    callback = function()
                                        filename = dialog:getInputValue()
                                        if filename == "" then
                                            filename = filename_original
                                        end
                                        UIManager:close(dialog)
                                        self.download_dialog:setTitle(createTitle(self.getCurrentDownloadDir(), filename))
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Book information"),
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                UIManager:show(TextViewer:new{
                    title = item.text,
                    title_multilines = true,
                    text = formatBookInformationDialogText(item.text, book_info),
                    text_type = "book_info",
                })
            end,
        },
    })

    local title = "No download links found."
    if #book_info.download_info_list > 0 then
        title = createTitle(self.getCurrentDownloadDir(), filename)
    elseif book_info.archived then
        title = "This book is archived. You must be move it back to Library if you want to download it."
    end

    self.download_dialog = ButtonDialog:new{
        title = title,
        buttons = buttons,
    }
    UIManager:show(self.download_dialog)
end

return KoboBrowser