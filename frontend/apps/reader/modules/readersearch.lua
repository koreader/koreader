local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local T = require("ffi/util").template

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local ReaderSearch = WidgetContainer:extend{
    direction = 0, -- 0 for search forward, 1 for search backward
    case_insensitive = true, -- default to case insensitive

    -- For a regex like [a-z\. ] many many hits are found, maybe the number of chars on a few pages.
    -- We don't try to catch them all as this is a reader and not a computer science playground. ;)
    -- So if some regex gets more than max_hits a notification will be shown.
    -- Increasing max_hits will slow down search for nasty regex. There is no slowdown for friendly
    -- regexs like `Max|Moritz` for `One|Two|Three`
    -- The speed of the search depends on the regexs. Complex ones might need some time, easy ones
    -- go with the speed of light.
    -- Setting max_hits higher, does not mean to require more memory. More hits means smaller single hits.
    max_hits = 2048, -- maximum hits for findText search; timinges tested on a Tolino
    findall_max_hits = 5000, -- maximum hits for findAllText search
     -- number of words before and after the search string in All search results
    findall_nb_context_words = G_reader_settings:readSetting("fulltext_search_nb_context_words") or 3,
    findall_results_per_page = G_reader_settings:readSetting("fulltext_search_results_per_page") or 10,

    -- internal: whether we expect results on previous pages
    -- (can be different from self.direction, if, from a page in the
    -- middle of a book, we search forward from start of book)
    _expect_back_results = false,
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)
end

local help_text = _([[
Regular expressions allow you to search for a matching pattern in a text. The simplest pattern is a simple sequence of characters, such as `James Bond`. There are many different varieties of regular expressions, but we support the ECMAScript syntax. The basics will be explained below.

If you want to search for all occurrences of 'Mister Moore', 'Sir Moore' or 'Alfons Moore' but not for 'Lady Moore'.
Enter 'Mister Moore|Sir Moore|Alfons Moore'.

If your search contains a special character from ^$.*+?()[]{}|\/ you have to put a \ before that character.

Examples:
Words containing 'os' -> '[^ ]+os[^ ]+'
Any single character '.' -> 'r.nge'
Any characters '.*' -> 'J.*s'
Numbers -> '[0-9]+'
Character range -> '[a-f]'
Not a space -> '[^ ]'
A word -> '[^ ]*[^ ]'
Last word in a sentence -> '[^ ]*\.'

Complex expressions may lead to an extremely long search time, in which case not all matches will be shown.]])

local SRELL_ERROR_CODES = {}
SRELL_ERROR_CODES[102] = _("Wrong escape '\\'")
SRELL_ERROR_CODES[103] = _("Back reference does not exist.")
SRELL_ERROR_CODES[104] = _("Mismatching brackets '[]'")
SRELL_ERROR_CODES[105] = _("Mismatched parens '()'")
SRELL_ERROR_CODES[106] = _("Mismatched brace '{}'")
SRELL_ERROR_CODES[107] = _("Invalid Range in '{}'")
SRELL_ERROR_CODES[108] = _("Invalid character range")
SRELL_ERROR_CODES[110] = _("No preceding expression in repetition.")
SRELL_ERROR_CODES[111] = _("Expression too complex, some hits will not be shown.")
SRELL_ERROR_CODES[666] = _("Expression may lead to an extremely long search time.")

function ReaderSearch:addToMainMenu(menu_items)
    menu_items.fulltext_search_settings = {
        text = _("Fulltext search settings"),
        sub_item_table = {
            {
                text = _("Show all results on text selection"),
                help_text = _("When invoked after text selection, show a list with all results instead of highlighting matches in book pages."),
                checked_func = function()
                    return G_reader_settings:isTrue("fulltext_search_find_all")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("fulltext_search_find_all")
                end,
            },
            {
                text_func = function()
                    return T(_("Words in context: %1"), self.findall_nb_context_words)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local widget = SpinWidget:new{
                        title_text =  _("Words in context"),
                        value = self.findall_nb_context_words,
                        value_min = 1,
                        value_max = 20,
                        default_value = 3,
                        callback = function(spin)
                            self.last_search_hash = nil
                            self.findall_nb_context_words = spin.value
                            G_reader_settings:saveSetting("fulltext_search_nb_context_words", spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
            {
                text_func = function()
                    return T(_("Results per page: %1"), self.findall_results_per_page)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local widget = SpinWidget:new{
                        title_text =  _("Results per page"),
                        value = self.findall_results_per_page,
                        value_min = 6,
                        value_max = 24,
                        default_value = 10,
                        callback = function(spin)
                            self.findall_results_per_page = spin.value
                            G_reader_settings:saveSetting("fulltext_search_results_per_page", spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
        },
    }
    menu_items.fulltext_search = {
        text = _("Fulltext search"),
        callback = function()
            self:onShowFulltextSearchInput()
        end,
    }
    menu_items.fulltext_search_findall_results = {
        text = _("Last fulltext search results"),
        callback = function()
            self:onShowFindAllResults()
        end,
    }
end

function ReaderSearch:searchText(text) -- from highlight dialog
    if G_reader_settings:isTrue("fulltext_search_find_all") then
        self.ui.highlight:clear()
        self:searchCallback(nil, text)
    else
        self:searchCallback(0, text) -- forward
    end
end

-- if reverse == 1 search backwards
function ReaderSearch:searchCallback(reverse, text)
    local search_text = text or self.input_dialog:getInputText()
    if search_text == nil or search_text == "" then return end
    self.ui.doc_settings:saveSetting("fulltext_search_last_search_text", search_text)
    self.last_search_text = search_text

    local regex_error
    if text then -- from highlight dialog
        self.use_regex = false
        self.case_insensitive = true
    else -- from input dialog
        -- search_text comes from our keyboard, and may contain multiple diacritics ordered
        -- in any order: we'd rather have them normalized, and expect the book content to
        -- be proper and normalized text.
        search_text = Utf8Proc.normalize_NFC(search_text)
        self.use_regex = self.check_button_regex.checked
        self.case_insensitive = not self.check_button_case.checked
        regex_error = self.use_regex and self.ui.document:checkRegex(search_text)
    end

    if self.use_regex and regex_error ~= 0 then
        logger.dbg("ReaderSearch: regex error", regex_error, SRELL_ERROR_CODES[regex_error])
        local error_message
        if SRELL_ERROR_CODES[regex_error] then
            error_message = T(_("Invalid regular expression:\n%1"), SRELL_ERROR_CODES[regex_error])
        else
            error_message = _("Invalid regular expression.")
        end
        UIManager:show(InfoMessage:new{ text = error_message })
    else
        UIManager:close(self.input_dialog)
        if reverse then
            self.last_search_hash = nil
            self:onShowSearchDialog(search_text, reverse, self.use_regex, self.case_insensitive)
        else
            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                self:findAllText(search_text)
            end)
        end
    end
end

function ReaderSearch:onShowFulltextSearchInput()
    local backward_text = "◁"
    local forward_text = "▷"
    if BD.mirroredUILayout() then
        backward_text, forward_text = forward_text, backward_text
    end
    self.input_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9),
        input = self.last_search_text or self.ui.doc_settings:readSetting("fulltext_search_last_search_text"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    -- @translators Find all results in entire document, button displayed on the search bar, should be short.
                    text = C_("Search text", "All"),
                    callback = function()
                        self:searchCallback()
                    end,
                },
                {
                    text = backward_text,
                    callback = function()
                        self:searchCallback(1)
                    end,
                },
                {
                    text = forward_text,
                    is_enter_default = true,
                    callback = function()
                        self:searchCallback(0)
                    end,
                },
            },
        },
    }

    self.check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = not self.case_insensitive,
        parent = self.input_dialog,
    }
    self.input_dialog:addWidget(self.check_button_case)
    self.check_button_regex = CheckButton:new{
        text = _("Regular expression (long-press for help)"),
        checked = self.use_regex,
        parent = self.input_dialog,
        hold_callback = function()
            UIManager:show(InfoMessage:new{
                text = help_text,
                width = Screen:getWidth() * 0.9,
            })
        end,
    }
    if self.ui.rolling then
        self.input_dialog:addWidget(self.check_button_regex)
    end

    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function ReaderSearch:onShowSearchDialog(text, direction, regex, case_insensitive)
    local neglect_current_location = false
    local current_page

    local function isSlowRegex(pattern)
        if pattern:find("%[") or pattern:find("%*") or pattern:find("%?") or pattern:find("%.") then
            return true
        end
        return false
    end
    local do_search = function(search_func, search_term, param)
        return function()
            local no_results = true -- for notification
            local res = search_func(self, search_term, param, regex, case_insensitive)
            if res then
                if self.ui.paging then
                    no_results = false
                    self.ui.link:onGotoLink({page = res.page - 1}, neglect_current_location)
                    self.view.highlight.temp[res.page] = res
                else
                    -- Was previously just:
                    --   self.ui.link:onGotoLink(res[1].start, neglect_current_location)

                    -- To avoid problems with edge cases, crengine may now give us links
                    -- that are on previous/next page of the page we should show. And
                    -- sometimes even xpointers that resolve to no page.
                    -- We need to loop thru all the results until we find one suitable,
                    -- to follow its link and go to the next/prev page with occurences.
                    local valid_link
                    -- If backward search, results are already in a reversed order, so we'll
                    -- start from the nearest to current page one.
                    for _, r in ipairs(res) do
                        -- result's start and end may be on different pages, we must
                        -- consider both
                        local r_start = r["start"]
                        local r_end = r["end"]
                        local r_start_page = self.ui.document:getPageFromXPointer(r_start)
                        local r_end_page = self.ui.document:getPageFromXPointer(r_end)
                        logger.dbg("res.start page & xpointer:", r_start_page, r_start)
                        logger.dbg("res.end page & xpointer:", r_end_page, r_end)
                        local bounds = {}
                        if self._expect_back_results then
                            -- Process end of occurence first, which is nearest to current page
                            table.insert(bounds, {r_end, r_end_page})
                            table.insert(bounds, {r_start, r_start_page})
                        else
                            table.insert(bounds, {r_start, r_start_page})
                            table.insert(bounds, {r_end, r_end_page})
                        end
                        for _, b in ipairs(bounds) do
                            local xpointer = b[1]
                            local page = b[2]
                            -- Look if it is valid for us
                            if page then -- it should resolve to a page
                                if not current_page then -- initial search
                                    -- We can (and should if there are) display results on current page
                                    current_page = self.ui.document:getCurrentPage()
                                    if (self._expect_back_results and page <= current_page) or
                                       (not self._expect_back_results and page >= current_page) then
                                        valid_link = xpointer
                                    end
                                else -- subsequent searches
                                    -- We must change page, so only consider results from
                                    -- another page, in the adequate search direction
                                    current_page = self.ui.document:getCurrentPage()
                                    if (self._expect_back_results and page < current_page) or
                                       (not self._expect_back_results and page > current_page) then
                                        valid_link = xpointer
                                    end
                                end
                            end
                            if valid_link then
                                break
                            end
                        end
                        if valid_link then
                            break
                        end
                    end
                    if valid_link then
                        no_results = false
                        self.ui.link:onGotoLink({xpointer=valid_link}, neglect_current_location)
                    end
                end
                -- Don't add result pages to location ("Go back") stack
                neglect_current_location = true
            end
            if no_results then
                local notification_text
                if self._expect_back_results then
                    notification_text = _("No results on preceding pages")
                else
                    notification_text = _("No results on following pages")
                end
                UIManager:show(Notification:new{
                    text = notification_text,
                })
            end
        end
    end
    local from_start_text = "▕◁"
    local backward_text = "◁"
    local forward_text = "▷"
    local from_end_text = "▷▏"
    if BD.mirroredUILayout() then
        backward_text, forward_text = forward_text, backward_text
        -- Keep the LTR order of |< and >|:
        from_start_text, from_end_text = BD.ltr(from_end_text), BD.ltr(from_start_text)
    end
    self.wait_button = ButtonDialog:new{
        buttons = {{{ text = "⌛" }}},
    }
    local function search(func, pattern, param)
        if regex and isSlowRegex(pattern) then
            return function()
                self.wait_button.alpha = 0.75
                self.wait_button.movable:setMovedOffset(self.search_dialog.movable:getMovedOffset())
                UIManager:show(self.wait_button)
                UIManager:tickAfterNext(function()
                    do_search(func, pattern, param)()
                    UIManager:close(self.wait_button)
                end)
            end
        else
            return do_search(func, pattern, param)
        end
    end
    self.search_dialog = ButtonDialog:new{
        -- alpha = 0.7,
        buttons = {
            {
                {
                    text = from_start_text,
                    vsync = true,
                    callback = search(self.searchFromStart, text, nil),
                },
                {
                    text = backward_text,
                    vsync = true,
                    callback = search(self.searchNext, text, 1),
                },
                {
                    icon = "appbar.search",
                    icon_width = Screen:scaleBySize(DGENERIC_ICON_SIZE * 0.8),
                    icon_height = Screen:scaleBySize(DGENERIC_ICON_SIZE * 0.8),
                    callback = function()
                        self.search_dialog:onClose()
                        self:onShowFulltextSearchInput()
                    end,
                },
                {
                    text = forward_text,
                    vsync = true,
                    callback = search(self.searchNext, text, 0),
                },
                {
                    text = from_end_text,
                    vsync = true,
                    callback = search(self.searchFromEnd, text, nil),
                },
            }
        },
        tap_close_callback = function()
            logger.dbg("highlight clear")
            self.ui.highlight:clear()
            UIManager:setDirty(self.dialog, "ui")
        end,
    }
    if regex and isSlowRegex(text) then
        self.wait_button.alpha = nil
        -- initial position: center of the screen
        UIManager:show(self.wait_button)
        UIManager:tickAfterNext(function()
            do_search(self.searchFromCurrent, text, direction)()
            UIManager:close(self.wait_button)
            UIManager:show(self.search_dialog)
            --- @todo regional
            UIManager:setDirty(self.dialog, "partial")
        end)
    else
        do_search(self.searchFromCurrent, text, direction)()
        UIManager:show(self.search_dialog)
        --- @todo regional
        UIManager:setDirty(self.dialog, "partial")
    end

    return true
end

-- if regex == true, use regular expression in pattern
-- if case == true or nil, the search is case insensitive
function ReaderSearch:search(pattern, origin, regex, case_insensitive)
    logger.dbg("search pattern", pattern)
    local direction = self.direction
    local page = self.view.state.page
    if case_insensitive == nil then
        case_insensitive = true
    end
    Device:setIgnoreInput(true)
    local retval, words_found = self.ui.document:findText(pattern, origin, direction, case_insensitive, page, regex, self.max_hits)
    Device:setIgnoreInput(false)
    self:showErrorNotification(words_found, regex, self.max_hits)
    return retval
end

function ReaderSearch:showErrorNotification(words_found, regex, max_hits)
    regex = regex or self.use_regex
    max_hits = max_hits or self.findall_max_hits
    local regex_retval = regex and self.ui.document:getAndClearRegexSearchError()
    if regex and regex_retval ~= 0 then
        local error_message
        if SRELL_ERROR_CODES[regex_retval] then
            error_message = SRELL_ERROR_CODES[regex_retval]
        else
            error_message = _("Unspecified error")
        end
        UIManager:show(Notification:new{
            text = error_message,
            timeout = false,
        })
    elseif words_found and words_found >= max_hits then
        UIManager:show(Notification:new{
            text =_("Too many hits"),
            timeout = 4,
         })
    end
end

function ReaderSearch:searchFromStart(pattern, _, regex, case_insensitive)
    self.direction = 0
    self._expect_back_results = true
    return self:search(pattern, -1, regex, case_insensitive)
end

function ReaderSearch:searchFromEnd(pattern, _, regex, case_insensitive)
    self.direction = 1
    self._expect_back_results = false
    return self:search(pattern, -1, regex, case_insensitive)
end

function ReaderSearch:searchFromCurrent(pattern, direction, regex, case_insensitive)
    self.direction = direction
    self._expect_back_results = direction == 1
    return self:search(pattern, 0, regex, case_insensitive)
end

-- ignore current page and search next occurrence
function ReaderSearch:searchNext(pattern, direction, regex, case_insensitive)
    self.direction = direction
    self._expect_back_results = direction == 1
    return self:search(pattern, 1, regex, case_insensitive)
end

function ReaderSearch:findAllText(search_text)
    local last_search_hash = (self.last_search_text or "") .. tostring(self.case_insensitive) .. tostring(self.use_regex)
    local not_cached = self.last_search_hash ~= last_search_hash
    if not_cached then
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()
        local completed, res = Trapper:dismissableRunInSubprocess(function()
            return self.ui.document:findAllText(search_text,
                self.case_insensitive, self.findall_nb_context_words, self.findall_max_hits, self.use_regex)
        end, info)
        if not completed then return end
        UIManager:close(info)
        self.last_search_hash = last_search_hash
        self.findall_results = res
        self.findall_results_item_index = nil
    end
    if self.findall_results then
        self:onShowFindAllResults(not_cached)
    else
        UIManager:show(InfoMessage:new{ text = _("No results in the document") })
    end
end

function ReaderSearch:onShowFindAllResults(not_cached)
    if not self.last_search_hash or (not not_cached and self.findall_results == nil) then
        -- no cached results, show input dialog
        self:onShowFulltextSearchInput()
        return
    end

    if self.ui.rolling and not_cached then -- for ui.paging: items are built in KoptInterface:findAllText()
        for _, item in ipairs(self.findall_results) do
            -- PDF/Kopt shows full words when only some part matches; let's do the same with CRE
            local word = item.matched_text or ""
            if item.matched_word_prefix then
                word = item.matched_word_prefix .. word
            end
            if item.matched_word_suffix then
                word = word .. item.matched_word_suffix
            end
            -- Make this word bolder, using Poor Text Formatting provided by TextBoxWidget
            -- (we know this text ends up in a TextBoxWidget).
            local text = TextBoxWidget.PTF_BOLD_START .. word .. TextBoxWidget.PTF_BOLD_END
            -- append context before and after the word
            if item.prev_text then
                if not item.prev_text:find("%s$") then
                    text = " " .. text
                end
                text = item.prev_text .. text
            end
            if item.next_text then
                if not item.next_text:find("^[%s%p]") then
                    text = text .. " "
                end
                text = text .. item.next_text
            end
            text = TextBoxWidget.PTF_HEADER .. text -- enable handling of our bold tags
            item.text = text
            item.mandatory = self.ui.bookmark:getBookmarkPageString(item.start)
        end
    end

    local menu
    menu = Menu:new{
        title = T(_("Search results (%1)"), #self.findall_results),
        subtitle = T(_("Query: %1"), self.last_search_text),
        items_per_page = self.findall_results_per_page,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuChoice = function(_, item)
            if self.ui.rolling then
                self.ui.link:addCurrentLocationToStack()
                self.ui.rolling:onGotoXPointer(item.start, item.start) -- show target line marker
                self.ui.document:getTextFromXPointers(item.start, item["end"], true) -- highlight
            else
                local page = item.mandatory
                local boxes = {}
                for i, box in ipairs(item.boxes) do
                    boxes[i] = self.ui.document:nativeToPageRectTransform(page, box)
                end
                self.ui.link:onGotoLink({ page = page - 1 })
                self.view.highlight.temp[page] = boxes
            end
        end,
        close_callback = function()
            self.findall_results_item_index = menu.page * menu.perpage -- save page number to reopen
            UIManager:close(menu)
        end,
    }
    menu:switchItemTable(nil, self.findall_results, self.findall_results_item_index)
    UIManager:show(menu)
    self:showErrorNotification(#self.findall_results)
end

return ReaderSearch
