--[[--
This module provides a way to display book information (filename and book metadata)
]]

local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local BookInfo = InputContainer:extend{
    bookinfo_menu_title = _("Book information"),
}

function BookInfo:init()
    if self.ui then -- only for Reader menu
        self.ui.menu:registerToMainMenu(self)
    end
end

function BookInfo:addToMainMenu(menu_items)
    menu_items.book_info = {
        text = self.bookinfo_menu_title,
        callback = function()
            -- Get them directly from ReaderUI's doc_settings
            local doc_props = self.ui.doc_settings:readSetting("doc_props")
            -- Make a copy, so we don't add "pages" to the original doc_props
            -- that will be saved at some point by ReaderUI.
            local book_props = {}
            for k, v in pairs(doc_props) do
                book_props[k] = v
            end
            book_props.pages = self.ui.doc_settings:readSetting("doc_pages")
            self:show(self.document.file, book_props)
        end,
    }
end

function BookInfo:isSupported(file)
    return lfs.attributes(file, "mode") == "file"
end

function BookInfo:show(file, book_props)
    local kv_pairs = {}

    local directory, filename = util.splitFilePathName(file)
    local filename_without_suffix, filetype = util.splitFileNameSuffix(filename) -- luacheck: no unused
    local file_size = lfs.attributes(file, "size") or 0
    local size_f = util.getFriendlySize(file_size)
    local size_b = util.getFormattedSize(file_size)
    local size = string.format("%s (%s bytes)", size_f, size_b)
    table.insert(kv_pairs, { _("Filename:"), filename })
    table.insert(kv_pairs, { _("Format:"), filetype:upper() })
    table.insert(kv_pairs, { _("Size:"), size })
    table.insert(kv_pairs, { _("Directory:"), filemanagerutil.abbreviate(directory) })
    table.insert(kv_pairs, "----")

    -- book_props may be provided if caller already has them available
    -- but it may lack 'pages', that we may get from sidecar file
    if not book_props or not book_props.pages then
        -- check there is actually a sidecar file before calling DocSettings:open()
        -- that would create an empty sidecar directory
        if DocSettings:hasSidecarFile(file) then
            local doc_settings = DocSettings:open(file)
            if doc_settings then
                if not book_props then
                    -- Files opened after 20170701 have a 'doc_props' setting with
                    -- complete metadata and 'doc_pages' with accurate nb of pages
                    book_props = doc_settings:readSetting('doc_props')
                end
                if not book_props then
                    -- File last opened before 20170701 may have a 'stats' setting
                    -- with partial metadata, or empty metadata if statistics plugin
                    -- was not enabled when book was read (we can guess that from
                    -- the fact that stats.page = 0)
                    local stats = doc_settings:readSetting('stats')
                    if stats and stats.pages ~= 0 then
                        -- Let's use them as is (which was what was done before), even if
                        -- incomplete, to avoid expensive book opening
                        book_props = stats
                    end
                end
                -- Files opened after 20170701 have an accurate 'doc_pages' setting
                local doc_pages = doc_settings:readSetting('doc_pages')
                if doc_pages and book_props then
                    book_props.pages = doc_pages
                end
            end
        end
    end

    -- If still no book_props (book never opened or empty 'stats'), open the
    -- document to get them
    if not book_props then
        local document = DocumentRegistry:openDocument(file)
        if document then
            local loaded = true
            local pages
            if document.loadDocument then -- CreDocument
                if not document:loadDocument() then
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
            DocumentRegistry:closeDocument(file)
        end
    end

    -- If still no book_props, fall back to empty ones
    if not book_props then
        book_props = {}
    end

    local title = book_props.title
    if title == "" or title == nil then title = _("N/A") end
    table.insert(kv_pairs, { _("Title:"), title })

    local authors = book_props.authors
    if authors == "" or authors == nil then authors = _("N/A") end
    table.insert(kv_pairs, { _("Authors:"), authors })

    local series = book_props.series
    if series == "" or series == nil then
        series = _("N/A")
    else -- Shorten calibre series decimal number (#4.0 => #4)
        series = series:gsub("(#%d+)%.0$", "%1")
    end
    table.insert(kv_pairs, { _("Series:"), series })

    local pages = book_props.pages
    if pages == "" or pages == nil then pages = _("N/A") end
    table.insert(kv_pairs, { _("Pages:"), pages })

    local language = book_props.language
    if language == "" or language == nil then language = _("N/A") end
    table.insert(kv_pairs, { _("Language:"), language })

    local keywords = book_props.keywords
    if keywords == "" or keywords == nil then keywords = _("N/A") end
    table.insert(kv_pairs, { _("Keywords:"), keywords })

    local description = book_props.description
    if description == "" or description == nil then
        description = _("N/A")
    else
        -- Description may (often in EPUB, but not always) or may not (rarely
        -- in PDF) be HTML.
        description = util.htmlToPlainTextIfHtml(book_props.description)
    end
    table.insert(kv_pairs, { _("Description:"), description })

    -- Cover image
    local viewCoverImage = function()
        local widget
        local document = DocumentRegistry:openDocument(file)
        if document then
            local cover_bb = document:getCoverPageImage()
            if cover_bb then
                widget = ImageViewer:new{
                    image = cover_bb,
                    with_title_bar = false,
                    fullscreen = true,
                }
            end
            DocumentRegistry:closeDocument(file)
        end
        if not widget then
            widget = InfoMessage:new{
                text = _("No cover image available"),
            }
        end
        UIManager:show(widget)
    end
    table.insert(kv_pairs, { _("Cover image:"), _("Tap to display"), callback=viewCoverImage })

    local widget = KeyValuePage:new{
        title = _("Book information"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
    }
    UIManager:show(widget)
end

return BookInfo
