--[[--
This module provides a way to display book information (filename and book metadata)
]]

local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local BookInfo = WidgetContainer:extend{
}

function BookInfo:init()
    if self.ui then -- only for Reader menu
        self.ui.menu:registerToMainMenu(self)
    end
end

function BookInfo:addToMainMenu(menu_items)
    menu_items.book_info = {
        text = _("Book information"),
        callback = function()
            self:onShowBookInfo()
        end,
    }
end

function BookInfo:show(file, book_props, metadata_updated_caller_callback)
    self.updated = nil
    local kv_pairs = {}

    -- File section
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
        book_props = self:getBookProps(file, book_props)
    end
    local values_lang
    local props = {
        { _("Title:"), "title" },
        { _("Authors:"), "authors" },
        { _("Series:"), "series" },
        { _("Pages:"), "pages" },
        { _("Language:"), "language" },
        { _("Keywords:"), "keywords" },
        { _("Description:"), "description" },
    }
    for _i, v in ipairs(props) do
        local prop_text, prop_key = unpack(v)
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
        elseif prop_key == "series" then
            -- If we were fed a BookInfo book_props (e.g., covermenu), series index is in a separate field
            if book_props.series_index then
                -- Here, we're assured that series_index is a Lua number, so round integers are automatically
                -- displayed without decimals
                prop = prop .. " #" .. book_props.series_index
            else
                -- But here, if we have a plain doc_props series with an index, drop empty decimals from round integers.
                prop = prop:gsub("(#%d+)%.0+$", "%1")
            end
        elseif prop_key == "language" then
            -- Get a chance to have title, authors... rendered with alternate
            -- glyphs for the book language (e.g. japanese book in chinese UI)
            values_lang = prop
        elseif prop_key == "description" then
            -- Description may (often in EPUB, but not always) or may not (rarely in PDF) be HTML
            prop = util.htmlToPlainTextIfHtml(prop)
        end
        table.insert(kv_pairs, { prop_text, prop })
    end
    -- cover image
    local is_doc = self.document and true or false
    self.custom_book_cover = DocSettings:findCoverFile(file)
    table.insert(kv_pairs, {
        _("Cover image:"),
        _("Tap to display"),
        callback = function() self:onShowBookCover(file, true) end,
        separator = is_doc and not self.custom_book_cover,
    })
    -- custom cover image
    if self.custom_book_cover then
        table.insert(kv_pairs, {
            _("Custom cover image:"),
            _("Tap to display"),
            callback = function() self:onShowBookCover(file) end,
            separator = is_doc,
        })
    end

    -- Page section
    if is_doc then
        local lines_nb, words_nb = self:getCurrentPageLineWordCounts()
        if lines_nb == 0 then
            lines_nb = _("N/A")
            words_nb = _("N/A")
        end
        table.insert(kv_pairs, { _("Current page lines:"), lines_nb })
        table.insert(kv_pairs, { _("Current page words:"), words_nb })
    end

    local KeyValuePage = require("ui/widget/keyvaluepage")
    self.kvp_widget = KeyValuePage:new{
        title = _("Book information"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
        values_lang = values_lang,
        close_callback = function()
            if self.updated then
                local FileManager = require("apps/filemanager/filemanager")
                local fm_ui = FileManager.instance
                local ui = self.ui or fm_ui
                if not ui then
                    local ReaderUI = require("apps/reader/readerui")
                    ui = ReaderUI.instance
                end
                if ui and ui.coverbrowser then
                    ui.coverbrowser:deleteBookInfo(file)
                end
                if fm_ui then
                    fm_ui:onRefresh()
                end
                if metadata_updated_caller_callback then
                    metadata_updated_caller_callback()
                end
            end
        end,
        title_bar_left_icon = "appbar.menu",
        title_bar_left_icon_tap_callback = function()
            self:showCustomMenu(file, book_props, metadata_updated_caller_callback)
        end,
    }
    UIManager:show(self.kvp_widget)
end

function BookInfo:getBookProps(file, book_props, no_open_document)
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
                -- Let's use them as is (which was what was done before), even if
                -- incomplete, to avoid expensive book opening
                book_props = stats
            end
        end
        -- Files opened after 20170701 have an accurate "doc_pages" setting.
        local doc_pages = doc_settings:readSetting("doc_pages")
        if doc_pages and book_props then
            book_props.pages = doc_pages
        end
    end

    -- If still no book_props (book never opened or empty "stats"), open the document to get them
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

    -- If still no book_props, fall back to empty ones
    return book_props or {}
end

function BookInfo:onShowBookInfo()
    if not self.document then return end
    -- Get them directly from ReaderUI's doc_settings
    local doc_props = self.ui.doc_settings:readSetting("doc_props")
    -- Make a copy, so we don't add "pages" to the original doc_props
    -- that will be saved at some point by ReaderUI.
    local book_props = { pages = self.ui.doc_settings:readSetting("doc_pages") }
    for k, v in pairs(doc_props) do
        book_props[k] = v
    end
    self:show(self.document.file, book_props)
end

function BookInfo:onShowBookDescription(description, file)
    if not description then
        if file then
            description = self:getBookProps(file).description
        elseif self.document then
            description = self.ui.doc_settings:readSetting("doc_props").description
                       or self.document:getProps().description
        end
    end
    if description and description ~= "" then
        -- Description may (often in EPUB, but not always) or may not (rarely
        -- in PDF) be HTML.
        description = util.htmlToPlainTextIfHtml(description)
        local TextViewer = require("ui/widget/textviewer")
        UIManager:show(TextViewer:new{
            title = _("Description:"),
            text = description,
        })
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
        local custom_cover = DocSettings:findCoverFile(file or (doc and doc.file))
        if custom_cover then
            local cover_doc = DocumentRegistry:openDocument(custom_cover)
            if cover_doc then
                cover_bb = cover_doc:getCoverPageImage()
                cover_doc:close()
                return cover_bb
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

function BookInfo:setCustomBookCover(file, book_props, metadata_updated_caller_callback)
    local function kvp_update()
        if self.ui then
            self.ui.doc_settings:getCoverFile(true) -- reset cover file cache
        end
        self.updated = true
        self.kvp_widget:onClose()
        if self.document then
            self:onShowBookInfo()
        else
            self:show(file, book_props, metadata_updated_caller_callback)
        end
    end
    if self.custom_book_cover then -- reset custom cover
        local ConfirmBox = require("ui/widget/confirmbox")
        local confirm_box = ConfirmBox:new{
            text = _("Reset custom cover?\nImage file will be deleted."),
            ok_text = _("Reset"),
            ok_callback = function()
                if os.remove(self.custom_book_cover) then
                    DocSettings:removeSidecarDir(file, util.splitFilePathName(self.custom_book_cover))
                    kvp_update()
                end
            end,
        }
        UIManager:show(confirm_box)
    else -- choose an image and set custom cover
        local PathChooser = require("ui/widget/pathchooser")
        local path_chooser = PathChooser:new{
            select_directory = false,
            file_filter = function(filename)
                return util.arrayContains(DocSettings.cover_ext, util.getFileNameSuffix(filename))
            end,
            onConfirm = function(image_file)
                local sidecar_dir
                local sidecar_file = DocSettings:findCoverFile(file) -- existing cover file
                if sidecar_file then
                    os.remove(sidecar_file)
                else -- no existing cover, get metadata file path
                    sidecar_file = DocSettings:hasSidecarFile(file, true) -- new sdr locations only
                end
                if sidecar_file then
                    sidecar_dir = util.splitFilePathName(sidecar_file)
                else -- no sdr folder, create new
                    sidecar_dir = DocSettings:getSidecarDir(file)
                    util.makePath(sidecar_dir)
                end
                local new_cover_file = sidecar_dir .. "/" .. "cover." .. util.getFileNameSuffix(image_file)
                if ffiutil.copyFile(image_file, new_cover_file) == nil then
                    kvp_update()
                end
            end,
        }
        UIManager:show(path_chooser)
    end
end

function BookInfo:getCurrentPageLineWordCounts()
    local lines_nb, words_nb = 0, 0
    if self.ui.rolling then
        local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(),
            false, false) -- do not highlight
        if res then
            lines_nb = #self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
            for word in util.gsplit(res.text, "[%s%p]+", false) do
                if util.hasCJKChar(word) then
                    for char in util.gsplit(word, "[\192-\255][\128-\191]+", true) do
                        words_nb = words_nb + 1
                    end
                else
                    words_nb = words_nb + 1
                end
            end
        end
    else
        local page_boxes = self.ui.document:getTextBoxes(self.ui:getCurrentPage())
        if page_boxes and page_boxes[1][1].word then
            lines_nb = #page_boxes
            for _, line in ipairs(page_boxes) do
                if #line == 1 and line[1].word == "" then -- empty line
                    lines_nb = lines_nb - 1
                else
                    words_nb = words_nb + #line
                    local last_word = line[#line].word
                    if last_word:sub(-1) == "-" and last_word ~= "-" then -- hyphenated
                        words_nb = words_nb - 1
                    end
                end
            end
        end
    end
    return lines_nb, words_nb
end

function BookInfo:showCustomMenu(file, book_props, metadata_updated_caller_callback)
    local button_dialog
    local buttons = {{
        {
            text = self.custom_book_cover and _("Reset cover image") or _("Set cover image"),
            align = "left",
            callback = function()
                UIManager:close(button_dialog)
                self:setCustomBookCover(file, book_props, metadata_updated_caller_callback)
            end,
        },
    }}
    button_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.kvp_widget.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(button_dialog)
end

return BookInfo
