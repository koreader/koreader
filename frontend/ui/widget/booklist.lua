local DocSettings = require("docsettings")
local Menu = require("ui/widget/menu")
local Utf8Proc = require("ffi/utf8proc")
local datetime = require("datetime")
local ffiUtil = require("ffi/util")
local sort = require("sort")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

local BookList = Menu:extend{
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    is_borderless = true,
    is_popout = false,
    book_info_cache = {}, -- cache in the base class
}

BookList.collates = {
    strcoll = {
        text = _("name"),
        menu_order = 10,
        can_collate_mixed = true,
        init_sort_func = function()
            return function(a, b)
                return ffiUtil.strcoll(a.text, b.text)
            end
        end,
    },
    natural = {
        text = _("name (natural sorting)"),
        menu_order = 20,
        can_collate_mixed = true,
        init_sort_func = function(cache)
            local natsort
            natsort, cache = sort.natsort_cmp(cache)
            return function(a, b)
                return natsort(a.text, b.text)
            end, cache
        end,
    },
    access = {
        text = _("last read date"),
        menu_order = 30,
        can_collate_mixed = true,
        init_sort_func = function()
            return function(a, b)
                return a.attr.access > b.attr.access
            end
        end,
        mandatory_func = function(item)
            return datetime.secondsToDateTime(item.attr.access)
        end,
    },
    date = {
        text = _("date modified"),
        menu_order = 40,
        can_collate_mixed = true,
        init_sort_func = function()
            return function(a, b)
                return a.attr.modification > b.attr.modification
            end
        end,
        mandatory_func = function(item)
            return datetime.secondsToDateTime(item.attr.modification)
        end,
    },
    size = {
        text = _("size"),
        menu_order = 50,
        can_collate_mixed = false,
        init_sort_func = function()
            return function(a, b)
                return a.attr.size < b.attr.size
            end
        end,
    },
    type = {
        text = _("type"),
        menu_order = 60,
        can_collate_mixed = false,
        init_sort_func = function()
            return function(a, b)
                if (a.suffix or b.suffix) and a.suffix ~= b.suffix then
                    return ffiUtil.strcoll(a.suffix, b.suffix)
                end
                return ffiUtil.strcoll(a.text, b.text)
            end
        end,
        item_func = function(item)
            item.suffix = util.getFileNameSuffix(item.text)
        end,
    },
    percent_unopened_first = {
        text = _("percent - unopened first"),
        menu_order = 70,
        can_collate_mixed = false,
        init_sort_func = function()
            return function(a, b)
                if a.opened == b.opened then
                    if a.opened then
                        return a.percent_finished < b.percent_finished
                    end
                    return ffiUtil.strcoll(a.text, b.text)
                end
                return b.opened
            end
        end,
        item_func = function(item)
            local book_info = BookList.getBookInfo(item.path)
            item.opened = book_info.been_opened
            -- smooth 2 decimal points (0.00) instead of 16 decimal points
            item.percent_finished = util.round_decimal(book_info.percent_finished or 0, 2)
        end,
        mandatory_func = function(item)
            return item.opened and string.format("%d\u{202F}%%", 100 * item.percent_finished) or "–"
        end,
    },
    percent_unopened_last = {
        text = _("percent - unopened last"),
        menu_order = 80,
        can_collate_mixed = false,
        init_sort_func = function()
            return function(a, b)
                if a.opened == b.opened then
                    if a.opened then
                        return a.percent_finished < b.percent_finished
                    end
                    return ffiUtil.strcoll(a.text, b.text)
                end
                return a.opened
            end
        end,
        item_func = function(item)
            local book_info = BookList.getBookInfo(item.path)
            item.opened = book_info.been_opened
            -- smooth 2 decimal points (0.00) instead of 16 decimal points
            item.percent_finished = util.round_decimal(book_info.percent_finished or 0, 2)
        end,
        mandatory_func = function(item)
            return item.opened and string.format("%d\u{202F}%%", 100 * item.percent_finished) or "–"
        end,
    },
    percent_natural = {
        -- sort 90% > 50% > 0% > on hold > unopened > 100% or finished
        text = _("percent – unopened – finished last"),
        menu_order = 90,
        can_collate_mixed = false,
        init_sort_func = function(cache)
            local natsort
            natsort, cache = sort.natsort_cmp(cache)
            local sortfunc =  function(a, b)
                if a.sort_percent == b.sort_percent then
                    return natsort(a.text, b.text)
                elseif a.sort_percent == 1 then
                    return false
                elseif b.sort_percent == 1 then
                    return true
                else
                    return a.sort_percent > b.sort_percent
                end
            end
            return sortfunc, cache
        end,
        item_func = function(item)
            local book_info = BookList.getBookInfo(item.path)
            item.opened = book_info.been_opened
            local percent_finished = book_info.percent_finished
            local sort_percent
            if item.opened then
                -- books marked as "finished" or "on hold" should be considered the same as 100% and less than 0% respectively
                if book_info.status == "complete" then
                    sort_percent = 1.0
                elseif book_info.status == "abandoned" then
                    sort_percent = -0.01
                end
            end
            -- smooth 2 decimal points (0.00) instead of 16 decimal points
            item.sort_percent = sort_percent or util.round_decimal(percent_finished or -1, 2)
            item.percent_finished = percent_finished or 0
        end,
        mandatory_func = function(item)
            return item.opened and string.format("%d\u{202F}%%", 100 * item.percent_finished) or "–"
        end,
    },
    title = {
        text = _("Title"),
        menu_order = 100,
        item_func = function(item, ui)
            local doc_props = ui.bookinfo:getDocProps(item.path or item.file)
            item.doc_props = doc_props
        end,
        init_sort_func = function()
            return function(a, b)
                return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
            end
        end,
    },
    authors = {
        text = _("Authors"),
        menu_order = 110,
        item_func = function(item, ui)
            local doc_props = ui.bookinfo:getDocProps(item.path or item.file)
            doc_props.authors = doc_props.authors or "\u{FFFF}" -- sorted last
            item.doc_props = doc_props
        end,
        init_sort_func = function()
            return function(a, b)
                if a.doc_props.authors ~= b.doc_props.authors then
                    return ffiUtil.strcoll(a.doc_props.authors, b.doc_props.authors)
                end
                return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
            end
        end,
    },
    series = {
        text = _("Series"),
        menu_order = 120,
        item_func = function(item, ui)
            local doc_props = ui.bookinfo:getDocProps(item.path or item.file)
            doc_props.series = doc_props.series or "\u{FFFF}"
            item.doc_props = doc_props
        end,
        init_sort_func = function()
            return function(a, b)
                if a.doc_props.series ~= b.doc_props.series then
                    return ffiUtil.strcoll(a.doc_props.series, b.doc_props.series)
                end
                if a.doc_props.series_index and b.doc_props.series_index then
                    return a.doc_props.series_index < b.doc_props.series_index
                end
                return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
            end
        end,
    },
    keywords = {
        text = _("Keywords"),
        menu_order = 130,
        item_func = function(item, ui)
            local doc_props = ui.bookinfo:getDocProps(item.path or item.file)
            doc_props.keywords = doc_props.keywords or "\u{FFFF}"
            item.doc_props = doc_props
        end,
        init_sort_func = function()
            return function(a, b)
                if a.doc_props.keywords ~= b.doc_props.keywords then
                    return ffiUtil.strcoll(a.doc_props.keywords, b.doc_props.keywords)
                end
                return ffiUtil.strcoll(a.doc_props.display_title, b.doc_props.display_title)
            end
        end,
    },
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
    book_info.status = summary and summary.status
    if BookList.getBookStatusString(book_info.status) == nil then
        book_info.status = "reading"
    end
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

local status_strings = {
    all       = C_("Status of group of books", "All"),
    deleted   = C_("Status of group of books", "Deleted"),
    new       = C_("Status of group of books", "New"),      -- no sidecar file
    reading   = C_("Status of group of books", "Reading"),  -- doc_settings.summary.status
    abandoned = C_("Status of group of books", "On hold"),  -- doc_settings.summary.status
    complete  = C_("Status of group of books", "Finished"), -- doc_settings.summary.status
}

local status_strings_singular = {
    reading   = C_("Status of single book", "Reading"),
    abandoned = C_("Status of single book", "On hold"),
    complete  = C_("Status of single book", "Finished"),
}

function BookList.getBookStatusString(status, with_prefix, singular)
    local status_string = status and (singular and status_strings_singular[status] or status_strings[status])
    if status_string then
        if with_prefix then
            status_string = Utf8Proc.lowercase(util.fixUtf8(status_string, "?"))
            return T(_("Status: %1"), status_string)
        end
        return status_string
    end
end

return BookList
