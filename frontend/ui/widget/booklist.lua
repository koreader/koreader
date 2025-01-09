local DocSettings = require("docsettings")
local Menu = require("ui/widget/menu")

local BookList = Menu:extend{
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    is_borderless = true,
    is_popout = false,

    book_info_cache = nil, -- hashmap { been_opened, pages, percent_finished, status, has_highlight }
}

function BookList:init()
    self.title_bar_fm_style = not self.custom_title_bar
    Menu.init(self)
end

function BookList:getBookInfoCache(file)
    if self.book_info_cache then
        if self.book_info_cache[file] then
            return self.book_info_cache[file]
        end
    else
        self.book_info_cache = {}
    end
    self.book_info_cache[file] = {}
    local book_info = self.book_info_cache[file]
    if DocSettings:hasSidecarFile(file) then
        book_info.been_opened = true
        local doc_settings = DocSettings:open(file)
        local pages = doc_settings:readSetting("doc_pages")
        if pages == nil then
            local stats = doc_settings:readSetting("stats")
            if stats and stats.pages and stats.pages ~= 0 then -- crengine with statistics disabled stores 0
                pages = stats.pages
            end
        end
        book_info.pages = pages
        book_info.percent_finished = doc_settings:readSetting("percent_finished")
        local summary = doc_settings:readSetting("summary")
        book_info.status = summary and summary.status
        local annotations = doc_settings:readSetting("annotations")
        if annotations then
            book_info.has_highlight = #annotations > 0
        else
            local highlight = doc_settings:readSetting("highlight")
            book_info.has_highlight = highlight and next(highlight) and true
        end
    else
        book_info.been_opened = false
    end
    return book_info
end

function BookList:getBookInfoCacheBeenOpened(file)
    local been_opened = self.book_info_cache and self.book_info_cache[file] and self.book_info_cache[file].been_opened
    if been_opened ~= nil then
        return been_opened
    end
    return DocSettings:hasSidecarFile(file)
end

function BookList:setBookInfoCache(file, status)
    local book_info_cache = self.book_info_cache and self.book_info_cache[file]
    if book_info_cache then
        book_info_cache.been_opened = true
        book_info_cache.status = status
    end
end

function BookList:resetBookInfoCache(file)
    if self.book_info_cache then
        self.book_info_cache[file] = nil
    end
end

return BookList
