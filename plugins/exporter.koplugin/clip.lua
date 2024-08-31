local DocumentRegistry = require("document/documentregistry")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local ffiutil = require("ffi/util")
local md5 = require("ffi/sha2").md5
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local MyClipping = {
    my_clippings = "/mnt/us/documents/My Clippings.txt",
}

function MyClipping:new(o)
    if o == nil then o = {} end
    setmetatable(o, self)
    self.__index = self
    return o
end

--[[
-- clippings: main table to store parsed highlights and notes entries
-- {
--      ["Title(Author Name)"] = {
--          {
--              {
--                  ["page"] = 123,
--                  ["time"] = 1398127554,
--                  ["text"] = "Games of all sorts were played in homes and fields."
--              },
--              {
--                  ["page"] = 156,
--                  ["time"] = 1398128287,
--                  ["text"] = "There Spenser settled down to gentleman farming.",
--                  ["note"] = "This is a sample note.",
--              },
--              ["title"] = "Chapter I"
--          },
--      }
-- }
-- ]]
function MyClipping:parseMyClippings()
    -- My Clippings format:
    -- Title(Author Name)
    -- Your Highlight on Page 123 | Added on Monday, April 21, 2014 10:08:07 PM
    --
    -- This is a sample highlight.
    -- ==========
    local file = io.open(self.my_clippings, "r")
    local clippings = {}
    if file then
        local index = 1
        local title, author, info, text
        for line in file:lines() do
            line = line:match("^%s*(.-)%s*$") or ""
            if index == 1 then
                title, author = self:parseTitleFromPath(line)
                clippings[title] = clippings[title] or {
                    title = title,
                    author = author,
                }
            elseif index == 2 then
                info = self:getInfo(line)
            -- elseif index == 3 then
            -- should be a blank line, we skip this line
            elseif index == 4 then
                text = self:getText(line)
            end
            if line == "==========" then
                if index == 5 then
                    -- entry ends normally
                    local clipping = {
                        page = info.page or info.location,
                        sort = info.sort,
                        time = info.time,
                        text = text,
                    }
                    -- we cannot extract chapter info so just insert clipping
                    -- to a place holder chapter
                    table.insert(clippings[title], { clipping })
                end
                index = 0
            end
            index = index + 1
        end
        file:close()
    end

    return clippings
end

local extensions = {
    [".pdf"] = true,
    [".djvu"] = true,
    [".epub"] = true,
    [".fb2"] = true,
    [".mobi"] = true,
    [".txt"] = true,
    [".html"] = true,
    [".doc"] = true,
}

local function isEmpty(s)
    return s == nil or s == ""
end

-- first attempt to parse from document metadata
-- remove file extensions added by former KOReader
-- extract author name in "Title(Author)" format
-- extract author name in "Title - Author" format
function MyClipping:parseTitleFromPath(line)
    line = line:match("^%s*(.-)%s*$") or ""
    if extensions[line:sub(-4):lower()] then
        line = line:sub(1, -5)
    elseif extensions[line:sub(-5):lower()] then
        line = line:sub(1, -6)
    end
    local dummy, title, author
    dummy, dummy, title, author = line:find("(.-)%s*%((.*)%)")
    if not author then
        dummy, dummy, title, author = line:find("(.-)%s*-%s*(.*)")
    end
    title = title or line:match("^%s*(.-)%s*$")
    return isEmpty(title) and _("Unknown Book") or title,
           isEmpty(author) and _("Unknown Author") or author
end

local keywords = {
    ["highlight"] = {
        "Highlight",
        "标注",
    },
    ["note"] = {
        "Note",
        "笔记",
    },
    ["bookmark"] = {
        "Bookmark",
        "书签",
    },
}

local months = {
    ["Jan"] = 1,
    ["Feb"] = 2,
    ["Mar"] = 3,
    ["Apr"] = 4,
    ["May"] = 5,
    ["Jun"] = 6,
    ["Jul"] = 7,
    ["Aug"] = 8,
    ["Sep"] = 9,
    ["Oct"] = 10,
    ["Nov"] = 11,
    ["Dec"] = 12
}

local pms = {
    ["PM"] = 12,
    ["下午"] = 12,
}

function MyClipping:getTime(line)
    if not line then return end
    local _, _, year, month, day = line:find("(%d+)年(%d+)月(%d+)日")
    if not year or not month or not day then
        _, _, year, month, day = line:find("(%d%d%d%d)-(%d%d)-(%d%d)")
    end
    if not year or not month or not day then
        for k, v in pairs(months) do
            if line:find(k) then
                month = v
                _, _, day = line:find(" (%d?%d)[, ]")
                _, _, year = line:find(" (%d%d%d%d)")
                break
            end
        end
    end

    local _, _, hour, minute, second = line:find("(%d+):(%d+):(%d+)")
    if year and month and day and hour and minute and second then
        for k, v in pairs(pms) do
            if line:find(k) then
                hour = hour + v
                break
            end
        end
        local time = os.time({
            year = year, month = month, day = day,
            hour = hour, min = minute, sec = second,
        })

        return time
    end
end

function MyClipping:getInfo(line)
    local info = {}
    line = line or ""
    local _, _, part1, part2 = line:find("(.+)%s*|%s*(.+)")

    -- find entry type and location
    for sort, words in pairs(keywords) do
        for _, word in ipairs(words) do
            if part1 and part1:find(word) then
                info.sort = sort
                info.location = part1:match("(%d+-?%d+)")
                break
            end
        end
    end

    -- find entry created time
    info.time = self:getTime(part2 or "")

    return info
end

function MyClipping:getText(line)
    line = line or ""
    return line:match("^%s*(.-)%s*$") or ""
end

-- get PNG string and md5 hash
function MyClipping:getImage(image)
    --DEBUG("image", image)
    local doc = DocumentRegistry:openDocument(image.file)
    if doc then
        local png = doc:clipPagePNGString(image.pos0, image.pos1,
                image.pboxes, image.drawer)
        --doc:clipPagePNGFile(image.pos0, image.pos1,
                --image.pboxes, image.drawer, "/tmp/"..md5(png)..".png")
        doc:close()
        if png then return { png = png, hash = md5(png) } end
    end
end

function MyClipping:parseAnnotations(annotations, book)
    local settings = G_reader_settings:readSetting("exporter")
    for _, item in ipairs(annotations) do
        if item.drawer and not (settings.highlight_styles and settings.highlight_styles[item.drawer] == false) then
            local clipping = {
                sort    = "highlight",
                page    = item.pageref or item.pageno,
                time    = self:getTime(item.datetime),
                text    = self:getText(item.text),
                note    = item.note and self:getText(item.note),
                chapter = item.chapter,
                drawer  = item.drawer,
                color   = item.color,
            }
            table.insert(book, { clipping })
        end
    end
end

function MyClipping:parseHighlight(highlights, bookmarks, book)
    --DEBUG("book", book.file)

    -- create a translated pattern that matches bookmark auto-text
    -- see ReaderBookmark:getBookmarkAutoText and ReaderBookmark:getBookmarkPageString
    --- @todo Remove this once we get rid of auto-text or improve the data model.
    local pattern = "^" .. T(_("Page %1 %2 @ %3"),
                               "%[?%d*%]?%d+",
                               "(.*)",
                               "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") .. "$"

    local orphan_highlights = {}
    local settings = G_reader_settings:readSetting("exporter")
    for page, items in pairs(highlights) do
        for _, item in ipairs(items) do
            if not (settings.highlight_styles and settings.highlight_styles[item.drawer] == false) then
                local clipping = {
                    sort    = "highlight",
                    page    = page,
                    time    = self:getTime(item.datetime or ""),
                    text    = self:getText(item.text),
                    chapter = item.chapter,
                    drawer  = item.drawer,
                }
                local bookmark_found = false
                for _, bookmark in pairs(bookmarks) do
                    if bookmark.datetime == item.datetime then
                        if bookmark.text then
                            local bookmark_quote = bookmark.text:match(pattern)
                            if bookmark_quote ~= clipping.text and bookmark.text ~= clipping.text then
                                -- use modified quoted text or entire bookmark text if it's not a match
                                clipping.note = bookmark_quote or bookmark.text
                            end
                        end
                        bookmark_found = true
                        break
                    end
                end
                if not bookmark_found then
                    table.insert(orphan_highlights, { clipping })
                end
                if item.text == "" and item.pos0 and item.pos1 and
                        item.pos0.x and item.pos0.y and
                        item.pos1.x and item.pos1.y then
                    -- highlights in reflowing mode don't have page in pos
                    if item.pos0.page == nil then item.pos0.page = page end
                    if item.pos1.page == nil then item.pos1.page = page end
                    local image = {}
                    image.file = book.file
                    image.pos0, image.pos1 = item.pos0, item.pos1
                    image.pboxes = item.pboxes
                    image.drawer = item.drawer
                    clipping.image = self:getImage(image)
                end
                --- @todo Store chapter info when exporting highlights.
                if (bookmark_found and clipping.text and clipping.text ~= "") or clipping.image then
                    table.insert(book, { clipping })
                end
            end
        end
    end
    -- A table to map bookmarks timestamp to index in the bookmarks table
    -- to facilitate sorting clippings by their position in the book
    -- since highlights are not sorted by position while bookmarks are.
    local bookmark_indexes = {}
    for i, bookmark in ipairs(bookmarks) do
        bookmark_indexes[self:getTime(bookmark.datetime)] = i
    end
    -- Sort clippings by their position in the book.
    table.sort(book, function(v1, v2) return bookmark_indexes[v1[1].time] > bookmark_indexes[v2[1].time] end)
     -- Place orphans at the end
    for _, v in ipairs(orphan_highlights) do
        table.insert(book, v)
    end
end

function MyClipping:getTitleAuthor(filepath, props)
    local _, _, doc_name = filepath:find(".*/(.*)")
    local parsed_title, parsed_author = self:parseTitleFromPath(doc_name)
    return isEmpty(props.title) and parsed_title or props.title,
           isEmpty(props.authors) and parsed_author or props.authors
end

function MyClipping:getClippingsFromBook(clippings, doc_path)
    local doc_settings = DocSettings:open(doc_path)
    local highlights, bookmarks
    local annotations = doc_settings:readSetting("annotations")
    if annotations == nil then
        highlights = doc_settings:readSetting("highlight")
        if highlights == nil then return end
        bookmarks = doc_settings:readSetting("bookmarks")
    end
    local props = doc_settings:readSetting("doc_props")
    props = FileManagerBookInfo.extendProps(props, doc_path)
    local title, author = self:getTitleAuthor(doc_path, props)
    clippings[title] = {
        file = doc_path,
        title = title,
        author = author,
        number_of_pages = doc_settings:readSetting("doc_pages"),
    }
    if annotations then
        self:parseAnnotations(annotations, clippings[title])
    else
        self:parseHighlight(highlights, bookmarks, clippings[title])
    end
end

function MyClipping:parseHistory()
    local clippings = {}
    for _, item in ipairs(require("readhistory").hist) do
        if not item.dim and DocSettings:hasSidecarFile(item.file) then
            self:getClippingsFromBook(clippings, item.file)
        end
    end
    return clippings
end

function MyClipping:parseFiles(files)
    local clippings = {}
    for file in pairs(files) do
        if DocSettings:hasSidecarFile(file) then
            self:getClippingsFromBook(clippings, file)
        end
    end
    return clippings
end

function MyClipping:parseCurrentDoc(view)
    local clippings = {}
    local title, author = self:getTitleAuthor(view.document.file, view.ui.doc_props)
    clippings[title] = {
        file = view.document.file,
        title = title,
        author = author,
        -- Replaces characters that are invalid in filenames.
        output_filename = util.getSafeFilename(title),
        number_of_pages = view.document.info.number_of_pages,
    }
    self:parseAnnotations(view.ui.annotation.annotations, clippings[title])
    return clippings
end

return MyClipping
