local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local Font = require("ui/font")
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

local ReaderSearch = InputContainer:new{
    direction = 0, -- 0 for search forward, 1 for search backward
    case_insensitive = true, -- default to case insensitive

    -- internal: whether we expect results on previous pages
    -- (can be different from self.direction, if, from a page in the
    -- middle of a book, we search forward from start of book)
    _expect_back_results = false,
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderSearch:addToMainMenu(menu_items)
    menu_items.fulltext_search = {
        text = _("Fulltext search"),
        callback = function()
            self:onShowFulltextSearchInput()
        end,
    }
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
        use_regex_checked = self.use_regex,
        case_insensitive_checked = self.case_insensitive,
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
                        if self.input_dialog:getInputText() == "" then return end
                        self.last_search_text = self.input_dialog:getInputText()
                        self.use_regex = self.check_button_regex.checked
                        self.case_insensitive = self.check_button_case.checked
                        if self.use_regex and self.ui.document:checkRegex(self.input_dialog:getInputText()) ~= 0 then
                            UIManager:show(InfoMessage:new{ text = _("Error in regular expression!") })
                        else
                            UIManager:close(self.input_dialog)
                            self:onShowSearchDialog(self.input_dialog:getInputText(), 1, self.use_regex, self.case_insensitive)
                        end
                    end,
                },
                {
                    text = forward_text,
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        self.last_search_text = self.input_dialog:getInputText()
                        self.use_regex = self.check_button_regex.checked
                        self.case_insensitive = self.check_button_case.checked
                        if self.use_regex and self.ui.document:checkRegex(self.input_dialog:getInputText()) ~= 0 then
                            UIManager:show(InfoMessage:new{ text = _("Error in regular expression!") })
                        else
                            UIManager:close(self.input_dialog)
                            self:onShowSearchDialog(self.input_dialog:getInputText(), 0, self.use_regex, self.case_insensitive)
                        end
                    end,
                },
            },
        },
    }

   -- checkboxes
    self.check_button_regex = self.check_button or CheckButton:new{
        text = _("Regular expression"),
        face = Font:getFace("smallinfofont"),
        checked = self.use_regex,
        callback = function()
            if not self.check_button_regex.checked then
                self.check_button_regex:check()
            else
                self.check_button_regex:unCheck()
            end
            self.input_dialog:onShow()
        end,
        padding = self.input_dialog.padding,
        margin = self.input_dialog.margin,
        bordersize = self.input_dialog.bordersize,
    }
    self.check_button_case = self.check_button or CheckButton:new{
        text = _("Case insensitive"),
        face = Font:getFace("smallinfofont"),
        checked = self.case_insensitive,
        callback = function()
            if not self.check_button_case.checked then
                self.check_button_case:check()
            else
                self.check_button_case:unCheck()
            end
            self.input_dialog:onShow()
        end,
        padding = self.input_dialog.padding,
        margin = self.input_dialog.margin,
        bordersize = self.input_dialog.bordersize,
    }

    local checkbox_shift = math.floor((self.input_dialog.width - self.input_dialog._input_widget.width) / 2 + 0.5)
    local check_buttons = HorizontalGroup:new{
        HorizontalSpan:new{width = checkbox_shift},
        HorizontalGroup:new{
            VerticalGroup:new{
                align = "left",
                self.check_button_regex,
                self.check_button_case,
            },
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
    self.search_dialog = ButtonDialog:new{
        -- alpha = 0.7,
        buttons = {
            {
                {
                    text = from_start_text,
                    vsync = true,
                    callback = do_search(self.searchFromStart, text, regex, case_insensitive),
                },
                {
                    text = backward_text,
                    vsync = true,
                    callback = do_search(self.searchNext, text, 1, regex, case_insensitive),
                },
                {
                    text = forward_text,
                    vsync = true,
                    callback = do_search(self.searchNext, text, 0, regex, case_insensitive),
                },
                {
                    text = from_end_text,
                    vsync = true,
                    callback = do_search(self.searchFromEnd, text, regex, case_insensitive),
                },
            }
        },
        tap_close_callback = function()
            logger.dbg("highlight clear")
            self.ui.highlight:clear()
            UIManager:setDirty(self.dialog, "ui")
        end,
    }
    do_search(self.searchFromCurrent, text, direction, regex)()
    UIManager:show(self.search_dialog)
    --- @todo regional
    UIManager:setDirty(self.dialog, "partial")
    return true
end

-- if regex==true use regular expression in pattern
-- if case == true or nil the search is case insensitive
function ReaderSearch:search(pattern, origin, regex, case_insensitive)
    logger.dbg("search pattern", pattern)
    local direction = self.direction
    local page = self.view.state.page
    if case_insensitive == nil then
        case_insensitive = true
    end
    return self.ui.document:findText(pattern, origin, direction, case_insensitive, page, regex)
end

function ReaderSearch:searchFromStart(pattern, regex, case_insensitive)
    self.direction = 0
    self._expect_back_results = true
    return self:search(pattern, -1, regex, case_insensitive)
end

function ReaderSearch:searchFromEnd(pattern, regex, case_insensitive)
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
