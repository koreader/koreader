local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderSearch = InputContainer:new{
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
    max_hits = 2048, -- maximum hits for search; timinges tested on a Tolino

    -- internal: whether we expect results on previous pages
    -- (can be different from self.direction, if, from a page in the
    -- middle of a book, we search forward from start of book)
    _expect_back_results = false,
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)
end

local help_text = [[Regular expressions allow you to search for a matching pattern in a text. The simplest pattern is a simple sequence of characters, such as `James Bond`. There are many different varieties of regular expressions, but we support the ECMAScript syntax. The basics will be explained below.

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

Complex expressions may lead to an extremely long search time, in which case not all matches will be shown.
]]

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
    menu_items.fulltext_search = {
        text = _("Fulltext search"),
        callback = function()
            self:onShowFulltextSearchInput()
        end,
    }
end

-- if reverse ~= 0 search backwards
function ReaderSearch:searchCallback(reverse)
    if self.input_dialog:getInputText() == "" then return end
    self.last_search_text = self.input_dialog:getInputText()
    self.use_regex = self.check_button_regex.checked
    self.case_insensitive = not self.check_button_case.checked
    local regex_error = self.use_regex and self.ui.document:checkRegex(self.input_dialog:getInputText())
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
        self:onShowSearchDialog(self.input_dialog:getInputText(), reverse, self.use_regex, self.case_insensitive)
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
        input = self.last_search_text,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.input_dialog)
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

    -- checkboxes
    self.check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = not self.case_insensitive,
        parent = self.input_dialog,
        callback = function()
            if not self.check_button_case.checked then
                self.check_button_case:check()
            else
                self.check_button_case:unCheck()
            end
        end,
    }
    self.check_button_regex = CheckButton:new{
        text = _("Regular expression (hold for help)"),
        checked = self.use_regex,
        parent = self.input_dialog,
        callback = function()
            if not self.check_button_regex.checked then
                self.check_button_regex:check()
            else
                self.check_button_regex:unCheck()
            end
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new{ text = help_text })
        end,
    }

    local checkbox_shift = math.floor((self.input_dialog.width - self.input_dialog._input_widget.width) / 2 + 0.5)
    local check_buttons = HorizontalGroup:new{
        HorizontalSpan:new{width = checkbox_shift},
        VerticalGroup:new{
            align = "left",
            self.check_button_case,
            not self.ui.document.info.has_pages and self.check_button_regex or nil,
        },
    }

    -- insert check buttons before the regular buttons
    local nb_elements = #self.input_dialog.dialog_frame[1]
    table.insert(self.input_dialog.dialog_frame[1], nb_elements-1, check_buttons)

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
    local do_search = function(search_func, _text, param)
        return function()
            local no_results = true -- for notification
            local res = search_func(self, _text, param, regex, case_insensitive)
            if res then
                if self.ui.document.info.has_pages then
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
                    do_search(func, pattern, param, regex, case_insensitive)()
                    UIManager:close(self.wait_button)
                end)
            end
        else
            return do_search(func, pattern, param, regex, case_insensitive)
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
            do_search(self.searchFromCurrent, text, direction, regex, case_insensitive)()
            UIManager:close(self.wait_button)
            UIManager:show(self.search_dialog)
            --- @todo regional
            UIManager:setDirty(self.dialog, "partial")
        end)
    else
        do_search(self.searchFromCurrent, text, direction, regex, case_insensitive)()
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
    local regex_retval = regex and self.ui.document:getAndClearRegexSearchError();
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
    elseif words_found and words_found > self.max_hits then
        UIManager:show(Notification:new{
            text =_("Too many hits"),
            timeout = 4,
         })
    end
    return retval
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

return ReaderSearch
