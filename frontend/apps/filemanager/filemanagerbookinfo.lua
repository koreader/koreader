--[[--
This module provides a way to display book information (filename and book metadata)
]]

local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local Document = require("document/document")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template

local BookInfo = WidgetContainer:extend{
    title = _("Book information"),
    props = {
        "title",
        "authors",
        "series",
        "series_index",
        "language",
        "keywords",
        "description",
    },
    prop_text = {
        cover        = _("Cover image:"),
        title        = _("Title:"),
        authors      = _("Author(s):"),
        series       = _("Series:"),
        series_index = _("Series index:"),
        language     = _("Language:"),
        keywords     = _("Keywords:"),
        description  = _("Description:"),
        pages        = _("Pages:"),
    },
    rating_max = 5,
}

function BookInfo:init()
    if self.document then -- only for Reader menu
        self.ui.menu:registerToMainMenu(self)
    end
end

function BookInfo:addToMainMenu(menu_items)
    menu_items.book_info = {
        text = self.title,
        callback = function()
            self:onShowBookInfo()
        end,
    }
end

-- Shows book information.
function BookInfo:show(doc_settings_or_file, book_props)
    self.prop_updated = nil
    self.summary_updated = nil
    local kv_pairs = {}

    -- File section
    local has_sidecar = type(doc_settings_or_file) == "table"
    local file = has_sidecar and doc_settings_or_file:readSetting("doc_path") or doc_settings_or_file
    local folder, filename = util.splitFilePathName(file)
    local __, filetype = filemanagerutil.splitFileNameType(filename)
    local attr = lfs.attributes(file)
    local file_size = attr.size or 0
    local size_f = util.getFriendlySize(file_size)
    local size_b = util.getFormattedSize(file_size)
    table.insert(kv_pairs, { _("Filename:"), BD.filename(filename) })
    table.insert(kv_pairs, { _("Format:"), filetype:upper() })
    table.insert(kv_pairs, { _("Size:"), string.format("%s (%s bytes)", size_f, size_b) })
    table.insert(kv_pairs, { _("File date:"), os.date("%Y-%m-%d %H:%M:%S", attr.modification) })
    table.insert(kv_pairs, { _("Folder:"), BD.dirpath(filemanagerutil.abbreviate(folder)), separator = true })

    -- Book section
    -- book_props may be provided if caller already has them available
    -- but it may lack "pages", that we may get from sidecar file
    if not book_props or not book_props.pages then
        book_props = BookInfo.getDocProps(file, book_props)
    end
    -- cover image
    self.custom_book_cover = DocSettings:findCustomCoverFile(file)
    local key_text = self.prop_text["cover"]
    if self.custom_book_cover then
        key_text = "\u{F040} " .. key_text
    end
    table.insert(kv_pairs, { key_text, _("Tap to display"),
        callback = function()
            self:onShowBookCover(file)
        end,
        hold_callback = function()
            self:showCustomDialog(file, book_props)
        end,
        separator = true,
    })
    -- metadata
    local custom_props
    local custom_metadata_file = DocSettings:findCustomMetadataFile(file)
    if custom_metadata_file then
        self.custom_doc_settings = DocSettings.openSettingsFile(custom_metadata_file)
        custom_props = self.custom_doc_settings:readSetting("custom_props")
    end
    local values_lang, callback
    for _i, prop_key in ipairs(self.props) do
        local prop = book_props[prop_key]
        if prop == nil or prop == "" then
            prop = _("N/A")
        elseif prop_key == "title" then
            prop = BD.auto(prop)
        elseif prop_key == "authors" or prop_key == "keywords" then
            if prop:find("\n") then -- BD auto isolate each entry
                prop = util.splitToArray(prop, "\n")
                for i = 1, #prop do
                    prop[i] = BD.auto(prop[i])
                end
                prop = table.concat(prop, "\n")
            else
                prop = BD.auto(prop)
            end
        elseif prop_key == "language" then
            -- Get a chance to have title, authors... rendered with alternate
            -- glyphs for the book language (e.g. japanese book in chinese UI)
            values_lang = prop
        elseif prop_key == "description" then
            -- Description may (often in EPUB, but not always) or may not (rarely in PDF) be HTML
            prop = util.htmlToPlainTextIfHtml(prop)
            callback = function() -- proper text_type in TextViewer
                self:showBookProp("description", prop)
            end
        end
        key_text = self.prop_text[prop_key]
        if custom_props and custom_props[prop_key] then -- customized
            key_text = "\u{F040} " .. key_text
        end
        table.insert(kv_pairs, { key_text, prop,
            callback = callback,
            hold_callback = function()
                self:showCustomDialog(file, book_props, prop_key)
            end,
        })
    end
    -- pages
    table.insert(kv_pairs, { self.prop_text["pages"], book_props["pages"] or _("N/A"), separator = true })

    -- Current page
    if self.document then
        local lines_nb, words_nb = self.ui.view:getCurrentPageLineWordCounts()
        local text = lines_nb == 0 and _("number of lines and words not available")
            or T(N_("1 line", "%1 lines", lines_nb), lines_nb) .. ", " .. T(N_("1 word", "%1 words", words_nb), words_nb)
        table.insert(kv_pairs, { _("Current page:"), text, separator = true })
    end

    -- Summary section
    local summary = has_sidecar and doc_settings_or_file:readSetting("summary") or {}
    local rating = summary.rating or 0
    local summary_hold_callback = function()
        self:editSummary(doc_settings_or_file, book_props)
    end
    table.insert(kv_pairs, { _("Rating:"), ("★"):rep(rating) .. ("☆"):rep(self.rating_max - rating),
        hold_callback = summary_hold_callback })
    table.insert(kv_pairs, { _("Review:"), summary.note or _("N/A"),
        hold_callback = summary_hold_callback })

    local KeyValuePage = require("ui/widget/keyvaluepage")
    self.kvp_widget = KeyValuePage:new{
        title = self.title,
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
        values_lang = values_lang,
        close_callback = function()
            self.custom_doc_settings = nil
            self.custom_book_cover = nil
            if self.prop_updated then
                UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                UIManager:broadcastEvent(Event:new("BookMetadataChanged", self.prop_updated))
            end
            if self.summary_updated then -- refresh file browser, sdr folder may appear
                UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
            end
        end,
    }
    UIManager:show(self.kvp_widget)
end

function BookInfo.getCustomProp(prop_key, filepath)
    local custom_metadata_file = DocSettings:findCustomMetadataFile(filepath)
    return custom_metadata_file
        and DocSettings.openSettingsFile(custom_metadata_file):readSetting("custom_props")[prop_key]
end

-- Returns extended and customized metadata.
function BookInfo.extendProps(original_props, filepath)
    -- do not customize if filepath is not passed (eg from covermenu)
    local custom_metadata_file = filepath and DocSettings:findCustomMetadataFile(filepath)
    local custom_props = custom_metadata_file
        and DocSettings.openSettingsFile(custom_metadata_file):readSetting("custom_props") or {}
    original_props = original_props or {}

    local props = {}
    for _, prop_key in ipairs(BookInfo.props) do
        props[prop_key] = custom_props[prop_key] or original_props[prop_key]
    end
    props.pages = original_props.pages
    -- if original title is empty, generate it as filename without extension
    props.display_title = props.title or filemanagerutil.splitFileNameType(filepath)
    return props
end

-- Returns customized document metadata, including number of pages.
function BookInfo.getDocProps(file, book_props, no_open_document)
    if DocSettings:hasSidecarFile(file) then
        local doc_settings = DocSettings:open(file)
        if not book_props then
            -- Files opened after 20170701 have a "doc_props" setting with
            -- complete metadata and "doc_pages" with accurate nb of pages
            book_props = doc_settings:readSetting("doc_props")
        end
        if not book_props then
            -- File last opened before 20170701 may have a "stats" setting.
            -- with partial metadata, or empty metadata if statistics plugin
            -- was not enabled when book was read (we can guess that from
            -- the fact that stats.page = 0)
            local stats = doc_settings:readSetting("stats")
            if stats and stats.pages ~= 0 then
                -- title, authors, series, series_index, language
                book_props = Document:getProps(stats)
            end
        end
        -- Files opened after 20170701 have an accurate "doc_pages" setting.
        local doc_pages = doc_settings:readSetting("doc_pages")
        if doc_pages and book_props then
            book_props.pages = doc_pages
        end
    end

    -- If still no book_props (book never opened or empty "stats"),
    -- but custom metadata exists, it has a copy of original doc_props
    if not book_props then
        local custom_metadata_file = DocSettings:findCustomMetadataFile(file)
        if custom_metadata_file then
            book_props = DocSettings.openSettingsFile(custom_metadata_file):readSetting("doc_props")
        end
    end

    -- If still no book_props, open the document to get them
    if not book_props and not no_open_document then
        local document = DocumentRegistry:openDocument(file)
        if document then
            local loaded = true
            local pages
            if document.loadDocument then -- CreDocument
                if not document:loadDocument(false) then -- load only metadata
                    -- failed loading, calling other methods would segfault
                    loaded = false
                end
                -- For CreDocument, we would need to call document:render()
                -- to get nb of pages, but the nb obtained by simply calling
                -- here document:getPageCount() is wrong, often 2 to 3 times
                -- the nb of pages we see when opening the document (may be
                -- some other cre settings should be applied before calling
                -- render() ?)
            else
                -- for all others than crengine, we seem to get an accurate nb of pages
                pages = document:getPageCount()
            end
            if loaded then
                book_props = document:getProps()
                book_props.pages = pages
            end
            document:close()
        end
    end

    return BookInfo.extendProps(book_props, file)
end

function BookInfo:findInProps(book_props, search_string, case_sensitive)
    for _, key in ipairs(self.props) do
        local prop = book_props[key]
        if prop then
            if key == "series_index" then
                prop = tostring(prop)
            elseif key == "description" then
                prop = util.htmlToPlainTextIfHtml(prop)
            end
            if not case_sensitive then
                prop = Utf8Proc.lowercase(util.fixUtf8(prop, "?"))
            end
            if prop:find(search_string) then
                return true
            end
        end
    end
end

-- Shows book information for currently opened document.
function BookInfo:onShowBookInfo()
    if self.document then
        self.ui.doc_props.pages = self.ui.doc_settings:readSetting("doc_pages")
        self:show(self.ui.doc_settings, self.ui.doc_props)
    end
end

function BookInfo:showBookProp(prop_key, prop_text)
    UIManager:show(TextViewer:new{
        title = self.prop_text[prop_key],
        text = prop_text,
        text_type = prop_key == "description" and "book_info" or nil,
    })
end

function BookInfo:onShowBookDescription(description, file)
    if not description then
        if file then
            description = BookInfo.getDocProps(file).description
        elseif self.document then -- currently opened document
            description = self.ui.doc_props.description
        end
    end
    if description then
        self:showBookProp("description", util.htmlToPlainTextIfHtml(description))
    else
        UIManager:show(InfoMessage:new{
            text = _("No book description available."),
        })
    end
end

function BookInfo:onShowBookCover(file, force_orig)
    local cover_bb = self:getCoverImage(self.document, file, force_orig)
    if cover_bb then
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = cover_bb,
            with_title_bar = false,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
    else
        UIManager:show(InfoMessage:new{
            text = _("No cover image available."),
        })
    end
end

function BookInfo:getCoverImage(doc, file, force_orig)
    local cover_bb
    -- check for a custom cover (orig cover is forcibly requested in "Book information" only)
    if not force_orig then
        local custom_cover = DocSettings:findCustomCoverFile(file or (doc and doc.file))
        if custom_cover then
            local cover_doc = DocumentRegistry:openDocument(custom_cover)
            if cover_doc then
                cover_bb = cover_doc:getCoverPageImage()
                cover_doc:close()
                return cover_bb, custom_cover
            end
        end
    end
    -- orig cover
    local is_doc = doc and true or false
    if not is_doc then
        doc = DocumentRegistry:openDocument(file)
        if doc and doc.loadDocument then -- CreDocument
            doc:loadDocument(false) -- load only metadata
        end
    end
    if doc then
        cover_bb = doc:getCoverPageImage()
        if not is_doc then
            doc:close()
        end
    end
    return cover_bb
end

function BookInfo:updateBookInfo(file, book_props, prop_updated, prop_value_old)
    if self.document and prop_updated == "cover" then
        self.ui.doc_settings:getCustomCoverFile(true) -- reset cover file cache
    end
    self.prop_updated = {
        filepath = file,
        doc_props = book_props,
        metadata_key_updated = prop_updated,
        metadata_value_old = prop_value_old,
    }
    self.kvp_widget:onClose()
    self:show(file, book_props)
end

function BookInfo:setCustomCover(file, book_props)
    if self.custom_book_cover then -- reset custom cover
        if os.remove(self.custom_book_cover) then
            DocSettings.removeSidecarDir(util.splitFilePathName(self.custom_book_cover))
            self:updateBookInfo(file, book_props, "cover")
        end
    else -- choose an image and set custom cover
        local PathChooser = require("ui/widget/pathchooser")
        local path_chooser = PathChooser:new{
            select_directory = false,
            file_filter = function(filename)
                return DocumentRegistry:isImageFile(filename)
            end,
            onConfirm = function(image_file)
                if DocSettings:flushCustomCover(file, image_file) then
                    self:updateBookInfo(file, book_props, "cover")
                end
            end,
        }
        UIManager:show(path_chooser)
    end
end

function BookInfo:setCustomCoverFromImage(file, image_file)
    local custom_book_cover = DocSettings:findCustomCoverFile(file)
    if custom_book_cover then
        os.remove(custom_book_cover)
    end
    DocSettings:flushCustomCover(file, image_file)
    if self.ui.doc_settings then
        self.ui.doc_settings:getCustomCoverFile(true) -- reset cover file cache
    end
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
end

function BookInfo:setCustomMetadata(file, book_props, prop_key, prop_value)
    -- in file
    local custom_doc_settings, custom_props, display_title, no_custom_metadata
    if self.custom_doc_settings then
        custom_doc_settings = self.custom_doc_settings
    else -- no custom metadata file, create new
        custom_doc_settings = DocSettings.openSettingsFile()
        display_title = book_props.display_title -- backup
        book_props.display_title = nil
        custom_doc_settings:saveSetting("doc_props", book_props) -- save a copy of original props
    end
    custom_props = custom_doc_settings:readSetting("custom_props", {})
    local prop_value_old = custom_props[prop_key] or book_props[prop_key]
    custom_props[prop_key] = prop_value -- nil when resetting a custom prop
    if next(custom_props) == nil then -- no more custom metadata
        os.remove(custom_doc_settings.sidecar_file)
        DocSettings.removeSidecarDir(util.splitFilePathName(custom_doc_settings.sidecar_file))
        no_custom_metadata = true
    else
        if book_props.pages then -- keep a copy of original 'pages' up to date
            local original_props = custom_doc_settings:readSetting("doc_props")
            original_props.pages = book_props.pages
        end
        custom_doc_settings:flushCustomMetadata(file)
    end
    book_props.display_title = book_props.display_title or display_title -- restore
    -- in memory
    prop_value = prop_value or custom_doc_settings:readSetting("doc_props")[prop_key] -- set custom or restore original
    book_props[prop_key] = prop_value
    if prop_key == "title" then -- generate when resetting the customized title and original is empty
        book_props.display_title = book_props.title or filemanagerutil.splitFileNameType(file)
    end
    if self.document and self.document.file == file then -- currently opened document
        self.ui.doc_props[prop_key] = prop_value
        if prop_key == "title" then
            self.ui.doc_props.display_title = book_props.display_title
        end
        if no_custom_metadata then
            self.ui.doc_settings:getCustomMetadataFile(true) -- reset metadata file cache
        end
    end
    self:updateBookInfo(file, book_props, prop_key, prop_value_old)
end

function BookInfo:showCustomEditDialog(file, book_props, prop_key)
    local prop = book_props[prop_key]
    if prop and prop_key == "description" then
        prop = util.htmlToPlainTextIfHtml(prop)
    end
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Edit book metadata:") .. " " .. self.prop_text[prop_key]:gsub(":", ""),
        input = prop,
        input_type = prop_key == "series_index" and "number",
        allow_newline = prop_key == "authors" or prop_key == "keywords" or prop_key == "description",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local prop_value = input_dialog:getInputValue()
                        if prop_value and prop_value ~= "" then
                            UIManager:close(input_dialog)
                            self:setCustomMetadata(file, book_props, prop_key, prop_value)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function BookInfo:showCustomDialog(file, book_props, prop_key)
    local original_prop, custom_prop, prop_is_cover
    if prop_key then -- metadata
        if self.custom_doc_settings then
            original_prop = self.custom_doc_settings:readSetting("doc_props")[prop_key]
            custom_prop = self.custom_doc_settings:readSetting("custom_props")[prop_key]
        else
            original_prop = book_props[prop_key]
        end
        if original_prop and prop_key == "description" then
            original_prop = util.htmlToPlainTextIfHtml(original_prop)
        end
        prop_is_cover = false
    else -- cover
        prop_key = "cover"
        prop_is_cover = true
    end

    local button_dialog
    local buttons = {
        {
            {
                text = _("Copy original"),
                enabled = original_prop ~= nil and Device:hasClipboard(),
                callback = function()
                    UIManager:close(button_dialog)
                    Device.input.setClipboardText(original_prop)
                end,
            },
            {
                text = _("View original"),
                enabled = original_prop ~= nil or prop_is_cover,
                callback = function()
                    if prop_is_cover then
                        self:onShowBookCover(file, true)
                    else
                        self:showBookProp(prop_key, original_prop)
                    end
                end,
            },
        },
        {
            {
                text = _("Reset custom"),
                enabled = custom_prop ~= nil or (prop_is_cover and self.custom_book_cover ~= nil),
                callback = function()
                    local confirm_box = ConfirmBox:new{
                        text = prop_is_cover and _("Reset custom cover?\nImage file will be deleted.")
                                              or _("Reset custom book metadata field?"),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            UIManager:close(button_dialog)
                            if prop_is_cover then
                                self:setCustomCover(file, book_props)
                            else
                                self:setCustomMetadata(file, book_props, prop_key)
                            end
                        end,
                    }
                    UIManager:show(confirm_box)
                end,
            },
            {
                text = _("Set custom"),
                enabled = not prop_is_cover or (prop_is_cover and self.custom_book_cover == nil),
                callback = function()
                    UIManager:close(button_dialog)
                    if prop_is_cover then
                        self:setCustomCover(file, book_props)
                    else
                        self:showCustomEditDialog(file, book_props, prop_key)
                    end
                end,
            },
        },
    }
    button_dialog = ButtonDialog:new{
        title = _("Book metadata:") .. " " .. self.prop_text[prop_key]:gsub(":", ""),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function BookInfo:editSummary(doc_settings_or_file, book_props)
    local has_sidecar = type(doc_settings_or_file) == "table"
    local summary = has_sidecar and doc_settings_or_file:readSetting("summary") or {}
    local rating = summary.rating or 0
    local input_dialog
    local rating_buttons_row = {}
    for i = -1, self.rating_max + 2 do -- 2 empty buttons on each side
        if i < 1 or i > self.rating_max then
            table.insert(rating_buttons_row, {
                text = "",
                no_vertical_sep = true,
                enabled = false,
            })
        else
            table.insert(rating_buttons_row, {
                text = i <= rating and "★" or "☆",
                no_vertical_sep = true,
                callback = function()
                    UIManager:close(input_dialog)
                    local note = input_dialog:getInputText()
                    summary.note = note ~= "" and note or nil
                    summary.rating = (i == 1 and summary.rating == 1) and 0 or i
                    doc_settings_or_file = filemanagerutil.saveSummary(doc_settings_or_file, summary)
                    self.summary_updated = true
                    self.kvp_widget:onClose()
                    self:show(doc_settings_or_file, book_props)
                end,
            })
        end
    end
    input_dialog = InputDialog:new{
        title = _("Edit book review"),
        input = summary.note,
        text_height = Screen:scaleBySize(160),
        allow_newline = true,
        buttons = {
            rating_buttons_row,
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save review"),
                    callback = function()
                        UIManager:close(input_dialog)
                        local note = input_dialog:getInputText()
                        summary.note = note ~= "" and note or nil
                        doc_settings_or_file = filemanagerutil.saveSummary(doc_settings_or_file, summary)
                        self.summary_updated = true
                        self.kvp_widget:onClose()
                        self:show(doc_settings_or_file, book_props)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard(true)
end

function BookInfo:moveBookMetadata()
    -- called by filemanagermenu only
    local file_chooser = self.ui.file_chooser
    local function scanPath()
        local sys_folders = { -- do not scan sys_folders
            ["/dev"]  = true,
            ["/proc"] = true,
            ["/sys"]  = true,
        }
        local books_to_move = {}
        local dirs = { file_chooser.path }
        while #dirs ~= 0 do
            local new_dirs = {}
            for _, d in ipairs(dirs) do
                local ok, iter, dir_obj = pcall(lfs.dir, d)
                if ok then
                    for f in iter, dir_obj do
                        local fullpath = "/" .. f
                        if d ~= "/" then
                            fullpath = d .. fullpath
                        end
                        local attributes = lfs.attributes(fullpath) or {}
                        if attributes.mode == "directory" and f ~= "." and f ~= ".."
                                and file_chooser:show_dir(f) and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                                and file_chooser:show_file(f)
                                and DocSettings.isSidecarFileNotInPreferredLocation(fullpath) then
                            table.insert(books_to_move, fullpath)
                        end
                    end
                end
            end
            dirs = new_dirs
        end
        return books_to_move
    end
    UIManager:show(ConfirmBox:new{
        text = _("Scan books in current folder and subfolders for their metadata location?"),
        ok_text = _("Scan"),
        ok_callback = function()
            local books_to_move = scanPath()
            local books_to_move_nb = #books_to_move
            if books_to_move_nb == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No books with metadata not in your preferred location found."),
                })
            else
                UIManager:show(ConfirmBox:new{
                    text = T(N_("1 book with metadata not in your preferred location found.",
                              "%1 books with metadata not in your preferred location found.",
                              books_to_move_nb), books_to_move_nb) .. "\n" ..
                              _("Move book metadata to your preferred location?"),
                    ok_text = _("Move"),
                    ok_callback = function()
                        UIManager:close(self.menu_container)
                        for _, book in ipairs(books_to_move) do
                            DocSettings.updateLocation(book, book)
                        end
                        file_chooser:refreshPath()
                    end,
                })
            end
        end,
    })
end

function BookInfo.showBooksWithHashBasedMetadata()
    local header = T(_("Hash-based metadata has been saved in %1 for the following documents. Hash-based storage may slow down file browser navigation in large directories. Thus, if not using hash-based metadata storage, it is recommended to open the associated documents in KOReader to automatically migrate their metadata to the preferred storage location, or to delete %1, which will speed up file browser navigation."),
        DocSettings.getSidecarStorage("hash"))
    local file_info = { header .. "\n" }
    local sdrs = DocSettings.findSidecarFilesInHashLocation()
    for i, sdr in ipairs(sdrs) do
        local sidecar_file, custom_metadata_file = unpack(sdr)
        local doc_settings = DocSettings.openSettingsFile(sidecar_file)
        local doc_props = doc_settings:readSetting("doc_props")
        local custom_props = custom_metadata_file
            and DocSettings.openSettingsFile(custom_metadata_file):readSetting("custom_props") or {}
        local doc_path = doc_settings:readSetting("doc_path")
        local title = custom_props.title or doc_props.title or filemanagerutil.splitFileNameType(doc_path)
        local author = custom_props.authors or doc_props.authors or _("N/A")
        doc_path = lfs.attributes(doc_path, "mode") == "file" and doc_path or _("N/A")
        local text = T(_("%1. Title: %2; Author: %3\nDocument: %4"), i, title, author, doc_path)
        table.insert(file_info, text)
    end
    local doc_nb = #file_info - 1
    UIManager:show(TextViewer:new{
        title = T(N_("1 document with hash-based metadata", "%1 documents with hash-based metadata", doc_nb), doc_nb),
        title_multilines = true,
        text = table.concat(file_info, "\n"),
    })
end

return BookInfo
