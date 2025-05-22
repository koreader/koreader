local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local logger = require("logger")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local T = require("ffi/util").template

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local ReaderSearch = InputContainer:extend{
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

    -- internal: whether we expect results on previous pages
    -- (can be different from self.direction, if, from a page in the
    -- middle of a book, we search forward from start of book)
    _expect_back_results = false,
}

function ReaderSearch:init()
    self:registerKeyEvents()

     -- number of words before and after the search string in All search results
    self.findall_nb_context_words = G_reader_settings:readSetting("fulltext_search_nb_context_words") or 5
    self.findall_results_per_page = G_reader_settings:readSetting("fulltext_search_results_per_page") or 10
    self.findall_results_max_lines = G_reader_settings:readSetting("fulltext_search_results_max_lines")

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

function ReaderSearch:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowFulltextSearchInputBlank = { { "Alt", "Shift", "S" }, { "Ctrl", "Shift", "S" }, event = "ShowFulltextSearchInput", args = "" }
        self.key_events.ShowFulltextSearchInputRecent = { { "Alt", "S" }, { "Ctrl", "S" }, event = "ShowFulltextSearchInput" }
    end
end

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
                        value_max = 50,
                        default_value = 5,
                        value_hold_step = 5,
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
                    return T(_("Max lines per result: %1"), self.findall_results_max_lines or _("disabled"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local default_value = 4
                    local widget = SpinWidget:new{
                        title_text = _("Max lines per result"),
                        info_text = _("Set maximum number of lines to enable flexible item heights."),
                        value = self.findall_results_max_lines or default_value,
                        value_min = 1,
                        value_max = 10,
                        default_value = default_value,
                        ok_always_enabled = true,
                        callback = function(spin)
                            G_reader_settings:saveSetting("fulltext_search_results_max_lines", spin.value)
                            self.findall_results_max_lines = spin.value
                            self.last_search_hash = nil
                            touchmenu_instance:updateItems()
                        end,
                        extra_text = _("Disable"),
                        extra_callback = function()
                            G_reader_settings:delSetting("fulltext_search_results_max_lines")
                            self.findall_results_max_lines = nil
                            self.last_search_hash = nil
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
            {
                text_func = function()
                    local curr_perpage = self.findall_results_max_lines and _("flexible") or self.findall_results_per_page
                    return T(_("Results per page: %1"), curr_perpage)
                end,
                enabled_func = function()
                    return not self.findall_results_max_lines
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local widget = SpinWidget:new{
                        title_text =  _("Results per page"),
                        value = self.findall_results_per_page,
                        value_min = 2,
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
    self.start_page = self.ui.paging and self.view.state.page or self.ui.document:getXPointer()

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

function ReaderSearch:onShowFulltextSearchInput(search_string)
    local backward_text = "◁"
    local forward_text = "▷"
    if BD.mirroredUILayout() then
        backward_text, forward_text = forward_text, backward_text
    end
    self.input_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9),
        input = search_string or self.last_search_text or self.ui.doc_settings:readSetting("fulltext_search_last_search_text"),
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
                    if not current_page then -- initial search
                        current_page = self.ui.paging.current_page
                    end
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
                    -- to follow its link and go to the next/prev page with occurrences.
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
                            -- Process end of occurrence first, which is nearest to current page
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
                if not neglect_current_location then
                    -- Initial search: onGotoLink() has added the current page to the location stack,
                    -- and we don't want this to be done when showing further pages with results.
                    -- But if this initial search is showing results on the current page, we don't want
                    -- the original page added: we will do it when we jump to a different page.
                    -- For now, only do this with CreDocument. With PDF, whether in single page mode or
                    -- in scroll mode, the view can scroll a bit when showing results, and we want to
                    -- allow "go back" to restore the original viewport.
                    if self.ui.rolling and self.view.view_mode == "page" then
                        if current_page == self.ui.document:getCurrentPage() then
                            self.ui.link:popFromLocationStack()
                            neglect_current_location = false
                        else
                            -- We won't add further result pages to the location stack ("Go back").
                            neglect_current_location = true
                        end
                    end
                end
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

    if not_cached then
        for _, item in ipairs(self.findall_results) do
            local text = { TextBoxWidget.PTF_HEADER } -- use Poor Text Formatting provided by TextBoxWidget
            if item.prev_text then
                table.insert(text, item.prev_text) -- append context before the word
                if not item.prev_text:find("%s$") then -- separate prev context
                    table.insert(text, " ")
                end
            end
            table.insert(text, TextBoxWidget.PTF_BOLD_START) -- start of the word in bold
            -- PDF/Kopt shows full words when only some part matches; let's do the same with CRE
            table.insert(text, item.matched_word_prefix)
            table.insert(text, item.matched_text)
            table.insert(text, item.matched_word_suffix)
            table.insert(text, TextBoxWidget.PTF_BOLD_END) -- end of the word in bold
            if item.next_text then
                if not item.next_text:find("^[%s%p]") then -- separate next context
                    table.insert(text, " ")
                end
                table.insert(text, item.next_text) -- append context after the word
            end
            item.text = table.concat(text)

            local pageno = self.ui.rolling and self.ui.document:getPageFromXPointer(item.start) or item.start
            item.mandatory = self.ui.annotation:getPageRef(item.start, pageno) or pageno
            item.mandatory_dim_func = function()
                return pageno > self.ui:getCurrentPage()
            end
        end
    end

    self.result_menu = Menu:new{
        subtitle = T(_("Query: %1"), self.last_search_text),
        item_table = self.findall_results,
        items_per_page = self.findall_results_per_page,
        items_max_lines = self.findall_results_max_lines,
        multilines_forced = true, -- to always have search_string in bold
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showAllResultsMenuDialog() end,
        onMenuChoice = function(_menu_self, item)
            if self.ui.rolling then
                self.ui.link:addCurrentLocationToStack()
                self.ui.rolling:onGotoXPointer(item.start, item.start) -- show target line marker
                self.ui.document:getTextFromXPointers(item.start, item["end"], true) -- highlight
            else
                local page = item.start
                local boxes = {}
                for i, box in ipairs(item.boxes) do
                    boxes[i] = self.ui.document:nativeToPageRectTransform(page, box)
                end
                self.ui.link:onGotoLink({ page = page - 1 })
                self.view.highlight.temp[page] = boxes
            end
        end,
        onMenuHold = function(_menu_self, item)
            local text = T(_("Page: %1"), item.mandatory) .. "\n"
            local chapters = self.ui.toc:getFullTocTitleByPage(item.start)
            local last = "• " .. (table.remove(chapters) or "")
            local indent = ""
            if next(chapters) ~= nil then
                for _, level in ipairs(chapters) do
                    text = text .. indent .. "▾ " .. level .. "\n"
                    indent = indent .. " "
                end
            end
            UIManager:show(InfoMessage:new{ text = text .. indent .. last })
            return true
        end,
        close_callback = function()
            self.findall_results_item_index = self.result_menu:getFirstVisibleItemIndex() -- save page number to reopen
            UIManager:close(self.result_menu)
        end,
    }
    self:updateAllResultsMenu(nil, self.findall_results_item_index)
    UIManager:show(self.result_menu)
    self:showErrorNotification(#self.findall_results)
end

function ReaderSearch:updateAllResultsMenu(item_table, item_index)
    local items_nb = item_table and #item_table or #self.result_menu.item_table
    local title = T(_("Search results (%1)"), items_nb)
    self.result_menu:switchItemTable(title, item_table, item_index)
end

function ReaderSearch:showAllResultsMenuDialog()
    local item_table = self.result_menu.item_table
    local button_dialog
    local buttons = {
        {
            {
                text = _("All results"),
                callback = function()
                    UIManager:close(button_dialog)
                    self:updateAllResultsMenu(self.findall_results)
                end,
            },
        },
        {
            {
                text = _("Results in current chapter"),
                callback = function()
                    UIManager:close(button_dialog)
                    local current_chapter = self.ui.toc:getTocTitleOfCurrentPage()
                    local new_item_table = {}
                    local chapter_started
                    for _, item in ipairs(item_table) do
                        local item_chapter = self.ui.toc:getTocTitleByPage(item.start)
                        if item_chapter == current_chapter then
                            table.insert(new_item_table, item)
                            chapter_started = true
                        elseif chapter_started then -- chapter ended
                            break
                        end
                    end
                    self:updateAllResultsMenu(new_item_table)
                end,
            },
        },
        {}, -- separator
        {
            {
                text_func = function()
                    local pn = self.ui:getCurrentPage()
                    local pn_or_xp = self.ui.rolling and self.ui.rolling:getLastProgress() or pn
                    return T(_("Current page: %1"), self.ui.annotation:getPageRef(pn_or_xp, pn) or pn)
                end,
                callback = function()
                    UIManager:close(button_dialog)
                    local current_page = self.ui:getCurrentPage()
                    local index
                    for i = 1, #item_table do
                        local item = item_table[i]
                        local item_page = self.ui.rolling and self.ui.document:getPageFromXPointer(item.start) or item.start
                        if item_page == current_page then
                            index = i
                            break
                        elseif item_page > current_page then -- no search results in current page
                            index = i - 1
                            break
                        end
                    end
                    self:updateAllResultsMenu(nil, index or #item_table)
                end,
            },
        },
        {
            {
                text_func = function()
                    local pn = self.ui.rolling and self.ui.document:getPageFromXPointer(self.start_page) or self.start_page
                    return T(_("Go back to original page: %1"), self.ui.annotation:getPageRef(self.start_page, pn) or pn)
                end,
                callback = function()
                    UIManager:close(button_dialog)
                    self.result_menu.close_callback()
                    self:onGoToStartPage()
                end,
            },
        },
    }
    button_dialog = ButtonDialog:new{
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function ReaderSearch:onGoToStartPage()
    if self.start_page then
        if self.ui.rolling then
            self.ui.rolling:onGotoXPointer(self.start_page)
        else
            self.ui.paging:onGotoPage(self.start_page)
        end
    end
end

return ReaderSearch
