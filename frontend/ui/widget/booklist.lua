local DocSettings = require("docsettings")
local Menu = require("ui/widget/menu")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

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

-- BookInfo

function BookList.setBookInfoCache(file, doc_settings)
    local book_info = {
        been_opened      = true,
        status           = nil,
        pages            = nil,
        has_annotations  = nil,
        percent_finished = doc_settings:readSetting("percent_finished"),
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
        book_info.has_annotations = #annotations > 0
    else
        local highlight = doc_settings:readSetting("highlight")
        book_info.has_annotations = highlight and next(highlight) and true
    end
    BookList.book_info_cache[file] = book_info
end

function BookList.setBookInfoCacheProperty(file, prop_name, prop_value)
    if prop_name == "been_opened" and prop_value == false then
        BookList.book_info_cache[file] = { been_opened = false }
    else
        BookList.book_info_cache[file] = BookList.book_info_cache[file] or {}
        BookList.book_info_cache[file][prop_name] = prop_value
        BookList.book_info_cache[file].been_opened = true
    end
end

function BookList.resetBookInfoCache(file)
    BookList.book_info_cache[file] = nil
end

function BookList.hasBookInfoCache(file)
    local book_info = BookList.book_info_cache[file]
    return book_info ~= nil and (book_info.been_opened == false or book_info.status ~= nil)
end

function BookList.getBookInfo(file)
    if not BookList.hasBookInfoCache(file) then
        if DocSettings:hasSidecarFile(file) then
            BookList.setBookInfoCache(file, DocSettings:open(file))
        else
            BookList.book_info_cache[file] = { been_opened = false }
        end
    end
    return BookList.book_info_cache[file]
end

function BookList.hasBookBeenOpened(file)
    local book_info = BookList.book_info_cache[file]
    local been_opened = book_info and book_info.been_opened
    if been_opened == nil then -- not cached yet
        been_opened = DocSettings:hasSidecarFile(file)
        BookList.book_info_cache[file] = { been_opened = been_opened }
    end
    return been_opened
end

function BookList.getDocSettings(file)
    local doc_settings = DocSettings:open(file)
    if not BookList.hasBookInfoCache(file) then
        BookList.setBookInfoCache(file, doc_settings)
    end
    return doc_settings
end

function BookList.getBookStatus(file)
    local book_info = BookList.getBookInfo(file)
    return book_info.been_opened and book_info.status or "new"
end

function BookList.getBookStatusString(status, with_prefix)
    local status_string = ({
        new       = _("New"),      -- no sidecar file
        reading   = _("Reading"),  -- doc_settings.summary.status
        abandoned = _("On hold"),  -- doc_settings.summary.status
        complete  = _("Finished"), -- doc_settings.summary.status
        deleted   = _("Deleted"),
        all       = _("All"),
    })[status]
    return with_prefix and T(_("Status: %1"), status_string:lower()) or status_string
end

return BookList
