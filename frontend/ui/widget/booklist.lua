local DocSettings = require("docsettings")
local Menu = require("ui/widget/menu")

local BookList = Menu:extend{
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    is_borderless = true,
    is_popout = false,
    book_info_cache = {}, -- cache in the base class
}

function BookList:init()
    self.title_bar_fm_style = not self.custom_title_bar
    Menu.init(self)
end

function BookList._buildBookInfoCache(doc_settings)
    local book_info = {
        been_opened      = true,
        status           = nil,
        pages            = nil,
        percent_finished = doc_settings:readSetting("percent_finished"),
        has_highlight    = nil,
    }
    local summary = doc_settings:readSetting("summary")
    book_info.status = summary and summary.status or "reading"
    local pages = doc_settings:readSetting("doc_pages")
    if pages == nil then
        local stats = doc_settings:readSetting("stats")
        if stats and stats.pages and stats.pages ~= 0 then -- crengine with statistics disabled stores 0
            pages = stats.pages
        end
    end
    book_info.pages = pages
    local annotations = doc_settings:readSetting("annotations")
    if annotations then
        book_info.has_highlight = #annotations > 0
    else
        local highlight = doc_settings:readSetting("highlight")
        book_info.has_highlight = highlight and next(highlight) and true
    end
    return book_info
end

function BookList.getBookInfoCache(file)
    local book_info = BookList.book_info_cache[file]
    if (book_info and book_info.status) == nil then
        if DocSettings:hasSidecarFile(file) then
            BookList.book_info_cache[file] = BookList._buildBookInfoCache(DocSettings:open(file))
        else
            BookList.book_info_cache[file] = { been_opened = false }
        end
    end
    return BookList.book_info_cache[file]
end

function BookList.setBookInfoCache(file, status)
    local book_info = BookList.book_info_cache[file]
    if (book_info and book_info.status) == nil then
        BookList.book_info_cache[file] = { been_opened = true, status = status }
    else
        book_info.been_opened = true
        book_info.status = status
    end
end

function BookList.resetBookInfoCache(file)
    BookList.book_info_cache[file] = nil
end

function BookList.isBeenOpened(file)
    local book_info = BookList.book_info_cache[file]
    local been_opened = book_info and book_info.been_opened
    if been_opened == nil then -- not cached yet
        been_opened = DocSettings:hasSidecarFile(file)
        BookList.book_info_cache[file] = { been_opened = been_opened }
    end
    return been_opened
end

function BookList.openDocSettings(file)
    local doc_settings = DocSettings:open(file)
    local book_info = BookList.book_info_cache[file]
    if (book_info and book_info.status) == nil then
        BookList.book_info_cache[file] = BookList._buildBookInfoCache(doc_settings)
    end
    return doc_settings
end

return BookList
