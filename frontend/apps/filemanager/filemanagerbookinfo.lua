--[[--
This module provides a way to display book information (filename and book metadata)
]]

local BD = require("ui/bidi")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local BookInfo = WidgetContainer:extend{
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
            self:onShowBookInfo()
        end,
    }
end

function BookInfo:isSupported(file)
    return lfs.attributes(file, "mode") == "file"
end

function BookInfo:show(file, caller_book_props)
    local kv_pairs = {}

    local directory, filename = util.splitFilePathName(file)
    local filename_without_suffix, filetype = util.splitFileNameSuffix(filename) -- luacheck: no unused
    if filetype:lower() == "zip" then
        local filename_without_sub_suffix, sub_filetype = util.splitFileNameSuffix(filename_without_suffix) -- luacheck: no unused
        sub_filetype = sub_filetype:lower()
        local supported_sub_filetypes = { "fb2", "htm", "html", "log", "md", "txt" }

        for __, t in ipairs(supported_sub_filetypes) do
            if sub_filetype == t then
                filetype = sub_filetype .. "." .. filetype
                break
            end
        end
    end
    local file_size = lfs.attributes(file, "size") or 0
    local file_modification = lfs.attributes(file, "modification") or 0
    local size_f = util.getFriendlySize(file_size)
    local size_b = util.getFormattedSize(file_size)
    local size = string.format("%s (%s bytes)", size_f, size_b)
    table.insert(kv_pairs, { _("Filename:"), BD.filename(filename) })
    table.insert(kv_pairs, { _("Format:"), filetype:upper() })
    table.insert(kv_pairs, { _("Size:"), size })
    table.insert(kv_pairs, { _("File date:"), os.date("%Y-%m-%d %H:%M:%S", file_modification) })
    table.insert(kv_pairs, { _("Folder:"), BD.dirpath(filemanagerutil.abbreviate(directory)), separator = true })

    -- book_props may be provided if caller already has them available
    -- but it may lack "pages", that we may get from sidecar file
    local book_props = (caller_book_props and caller_book_props.pages) and caller_book_props
        or self:getBookProps(file, caller_book_props)

    local title = book_props.title
    if title == "" or title == nil then title = _("N/A") end
    table.insert(kv_pairs, { _("Title:"), BD.auto(title) })

    local authors = book_props.authors
    if authors == "" or authors == nil then
        authors = _("N/A")
    elseif authors:find("\n") then -- BD auto isolate each author
        authors = util.splitToArray(authors, "\n")
        for i=1, #authors do
            authors[i] = BD.auto(authors[i])
        end
        authors = table.concat(authors, "\n")
    else
        authors = BD.auto(authors)
    end
    table.insert(kv_pairs, { _("Authors:"), authors })

    local series = book_props.series
    if series == "" or series == nil then
        series = _("N/A")
    else
        -- If we were fed a BookInfo book_props (e.g., covermenu), series index is in a separate field
        if book_props.series_index then
            -- Here, we're assured that series_index is a Lua number, so round integers are automatically displayed without decimals
            series = book_props.series .. " #" .. book_props.series_index
        else
            -- But here, if we have a plain doc_props series with an index, drop empty decimals from round integers.
            series = book_props.series:gsub("(#%d+)%.0+$", "%1")
        end
    end
    table.insert(kv_pairs, { _("Series:"), BD.auto(series) })

    local pages = book_props.pages
    if pages == "" or pages == nil then pages = _("N/A") end
    table.insert(kv_pairs, { _("Pages:"), pages })

    local language = book_props.language
    if language == "" or language == nil then language = _("N/A") end
    table.insert(kv_pairs, { _("Language:"), language })

    local keywords = book_props.keywords
    if keywords == "" or keywords == nil then
        keywords = _("N/A")
    elseif keywords:find("\n") then -- BD auto isolate each keywords
        keywords = util.splitToArray(keywords, "\n")
        for i=1, #keywords do
            keywords[i] = BD.auto(keywords[i])
        end
        keywords = table.concat(keywords, "\n")
    else
        keywords = BD.auto(keywords)
    end
    table.insert(kv_pairs, { _("Keywords:"), keywords })

    local description = book_props.description
    if description == "" or description == nil then
        description = _("N/A")
    else
        -- Description may (often in EPUB, but not always) or may not (rarely
        -- in PDF) be HTML.
        description = util.htmlToPlainTextIfHtml(book_props.description)
    end
    -- (We don't BD wrap description: it may be multi-lines, and the value we set
    -- here may be viewed in a TextViewer that has auto_para_direction=true, which
    -- will show the right thing, that'd we rather not mess with BD wrapping.)
    table.insert(kv_pairs, { _("Description:"), description })

    -- Cover image
    local viewCoverImage = function()
        local widget
        local document = DocumentRegistry:openDocument(file)
        if document then
            if document.loadDocument then -- CreDocument
                document:loadDocument(false) -- load only metadata
            end
            local cover_bb = document:getCoverPageImage()
            if cover_bb then
                widget = ImageViewer:new{
                    image = cover_bb,
                    with_title_bar = false,
                    fullscreen = true,
                }
            end
            document:close()
        end
        if not widget then
            widget = InfoMessage:new{
                text = _("No cover image available"),
            }
        end
        UIManager:show(widget)
    end
    table.insert(kv_pairs, { _("Cover image:"), _("Tap to display"), callback=viewCoverImage })

    -- Get a chance to have title, authors... rendered with alternate
    -- glyphs for the book language (e.g. japanese book in chinese UI)
    local values_lang = nil
    if book_props.language and book_props.language ~= "" then
        values_lang = book_props.language
    end

    local widget = KeyValuePage:new{
        title = _("Book information"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
        values_lang = values_lang,
    }
    UIManager:show(widget)
end

function BookInfo:onShowBookInfo()
    if not self.document then return end
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
end

function BookInfo:onShowBookDescription(description, file)
    if file then
        description = self:getBookProps(file).description
    else
        if not description then
            description = self.document and self.document:getProps().description
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

function BookInfo:onShowBookCover(file)
    local document
    if file then
        document = DocumentRegistry:openDocument(file)
        if document and document.loadDocument then -- needed for crengine
            document:loadDocument(false) -- load only metadata
        end
    else
        document = self.document
    end
    if document then
        local cover_bb = document:getCoverPageImage()
        if cover_bb then
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
        document:close()
    end
end

function BookInfo:getBookProps(file, book_props)
    -- check there is actually a sidecar file before calling DocSettings:open()
    -- that would create an empty sidecar directory
    if DocSettings:hasSidecarFile(file) then
        local doc_settings = DocSettings:open(file)
        if doc_settings then
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
    end

    -- If still no book_props (book never opened or empty "stats"), open the
    -- document to get them
    if not book_props then
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

function BookInfo:showBookStatus(file, close_callback)
    local document = DocumentRegistry:openDocument(file)
    if not document then return end
    if document.loadDocument then
        document:loadDocument(false)
    end
    local doc_settings = DocSettings:open(file)
    local total_pages = doc_settings:readSetting("doc_pages")
    local current_page = doc_settings:readSetting("last_page")
    if total_pages and not current_page then
        current_page = math.floor(total_pages * doc_settings:readSetting("percent_finished"))
    end
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local status_page = BookStatusWidget:new {
        thumbnail = document:getCoverPageImage(),
        props = document:getProps(),
        settings = doc_settings,
        total_pages = total_pages,
        current_page = current_page,
        close_callback = close_callback,
    }
    UIManager:show(status_page, "full")
    document:close()
end

function BookInfo:markBookReadOrReading(file)
    -- "Read" ("Finished") status will be changed to "Reading"
    -- "Reading", "On hold" or no status will be changed to "Read" ("Finished")
    local docinfo = DocSettings:open(file)
    local old_status = docinfo.data.summary and docinfo.data.summary.status
    local status = old_status == "complete" and "reading" or "complete"
    if old_status then
        docinfo.data.summary.status = status
    else
        -- No BookStatus table, create a minimal one...
        if docinfo.data.summary then
            -- Err, a summary table with no status entry? Should never happen...
            local summary = { status = status }
            -- Append the status entry to the existing summary...
            util.tableMerge(docinfo.data.summary, summary)
        else
            -- No summary table at all, create a minimal one
            local summary = { status = status }
            docinfo:saveSetting("summary", summary)
        end
    end
    docinfo:flush()
    return status -- for covermenu
end

return BookInfo
