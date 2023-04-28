local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local DocSettings = require("docsettings")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
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
    local _, _, title, author = line:find("(.-)%s*%((.*)%)")
    if not author then
        _, _, title, author = line:find("(.-)%s*-%s*(.*)")
    end
    if not title then title = line end
    return title:match("^%s*(.-)%s*$"), author
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
                _, _, day = line:find(" (%d?%d),")
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
    for page, items in pairs(highlights) do
        for _, item in ipairs(items) do
            local clipping = {}
            clipping.page = page
            clipping.sort = "highlight"
            clipping.time = self:getTime(item.datetime or "")
            clipping.text = self:getText(item.text)
            clipping.chapter = item.chapter
            clipping.drawer = item.drawer
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

function MyClipping:parseHistoryFile(clippings, history_file, doc_file)
    if lfs.attributes(history_file, "mode") ~= "file"
    or not history_file:find(".+%.lua$") then
        return
    end
    if lfs.attributes(doc_file, "mode") ~= "file" then return end
    local ok, stored = pcall(dofile, history_file)
    if ok then
        if not stored then
            logger.warn("An empty history file ",
                        history_file,
                        "has been found. The book associated is ",
                        doc_file)
            return
        elseif not stored.highlight then
            return
        end
        local _, docname = util.splitFilePathName(doc_file)
        local parsed_title, parsed_author = self:parseTitleFromPath(util.splitFileNameSuffix(docname), doc_file)
        clippings[parsed_title] = {
            file = doc_file,
            title = stored.stats.title or parsed_title,
            author = stored.stats.authors or parsed_author,
        }
        self:parseHighlight(stored.highlight, stored.bookmarks, clippings[parsed_title])
    end
end

function MyClipping:parseHistory()
    local clippings = {}
    local history_dir = DataStorage:getHistoryDir()
    if lfs.attributes(history_dir, "mode") == "directory" then
        for f in lfs.dir(history_dir) do
            local legacy_history_file = ffiutil.joinPath(history_dir, f)
            if lfs.attributes(legacy_history_file, "mode") == "file" then
                local doc_file = DocSettings:getFileFromHistory(f)
                if doc_file then
                    self:parseHistoryFile(clippings, legacy_history_file, doc_file)
                end
            end
        end
    end
    for _, item in ipairs(require("readhistory").hist) do
        if not item.dim then
            self:parseHistoryFile(clippings, DocSettings:getSidecarFile(item.file, "doc"), item.file)
            self:parseHistoryFile(clippings, DocSettings:getSidecarFile(item.file, "dir"), item.file)
        end
    end
    return clippings
end

function MyClipping:getProps(file)
    local document = DocumentRegistry:openDocument(file)
    local book_props = nil
    if document then
        local loaded = true
        if document.loadDocument then -- CreDocument
            if not document:loadDocument(false) then -- load only metadata
                -- failed loading, calling other methods would segfault
                loaded = false
            end
        end
        if loaded then
            book_props = document:getProps()
        end
        document:close()
    end

    return book_props
end

local function isEmpty(s)
    return s == nil or s == ""
end

function MyClipping:getDocMeta(view)
    local props = self:getProps(view.document.file)
    local number_of_pages = view.document.info.number_of_pages
    local title = props.title
    local author = props.author or props.authors
    local path = view.document.file
    local _, _, docname = path:find(".*/(.*)")
    local parsed_title, parsed_author = self:parseTitleFromPath(docname)
    if isEmpty(title) then
        title = isEmpty(parsed_title) and "Unknown Book" or parsed_title
    end
    if isEmpty(author) then
        author = isEmpty(parsed_author) and "Unknown Author" or parsed_author
    end
    return {
        title = title,
        -- Replaces characters that are invalid in filenames.
        output_filename = util.getSafeFilename(title),
        author = author,
        number_of_pages = number_of_pages,
        file = view.document.file,
    }
end

function MyClipping:parseCurrentDoc(view)
    local clippings = {}
    local meta = self:getDocMeta(view)
    clippings[meta.title] = meta
    self:parseHighlight(view.highlight.saved, view.ui.bookmark.bookmarks, clippings[meta.title])
    return clippings
end

return MyClipping
