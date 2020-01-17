local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
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
    self:onInput{
        title = _("Enter text to search for"),
        type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = backward_text,
                    callback = function()
                        self:onShowSearchDialog(self.input_dialog:getInputText(), 1)
                        self:closeInputDialog()
                    end,
                },
                {
                    text = forward_text,
                    is_enter_default = true,
                    callback = function()
                        self:onShowSearchDialog(self.input_dialog:getInputText(), 0)
                        self:closeInputDialog()
                    end,
                },
            },
        },
    }
end

function ReaderSearch:onShowSearchDialog(text, direction)
    local neglect_current_location = false
    local current_page
    local do_search = function(search_func, _text, param)
        return function()
            local res = search_func(self, _text, param)
            if res then
                if self.ui.document.info.has_pages then
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
                        self.ui.link:onGotoLink({xpointer=valid_link}, neglect_current_location)
                    end
                end
                -- Don't add result pages to location ("Go back") stack
                neglect_current_location = true
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
                    callback = do_search(self.searchFromStart, text),
                },
                {
                    text = backward_text,
                    callback = do_search(self.searchNext, text, 1),
                },
                {
                    text = forward_text,
                    callback = do_search(self.searchNext, text, 0),
                },
                {
                    text = from_end_text,
                    callback = do_search(self.searchFromEnd, text),
                },
            }
        },
        tap_close_callback = function()
            logger.dbg("highlight clear")
            self.ui.highlight:clear()
            UIManager:setDirty(self.dialog, "ui")
        end,
    }
    do_search(self.searchFromCurrent, text, direction)()
    UIManager:show(self.search_dialog)
    --- @todo regional
    UIManager:setDirty(self.dialog, "partial")
    return true
end

function ReaderSearch:search(pattern, origin)
    logger.dbg("search pattern", pattern)
    if pattern == nil or pattern == '' then return end
    local direction = self.direction
    local case = self.case_insensitive
    local page = self.view.state.page
    return self.ui.document:findText(pattern, origin, direction, case, page)
end

function ReaderSearch:searchFromStart(pattern)
    self.direction = 0
    self._expect_back_results = true
    return self:search(pattern, -1)
end

function ReaderSearch:searchFromEnd(pattern)
    self.direction = 1
    self._expect_back_results = false
    return self:search(pattern, -1)
end

function ReaderSearch:searchFromCurrent(pattern, direction)
    self.direction = direction
    self._expect_back_results = direction == 1
    return self:search(pattern, 0)
end

-- ignore current page and search next occurrence
function ReaderSearch:searchNext(pattern, direction)
    self.direction = direction
    self._expect_back_results = direction == 1
    return self:search(pattern, 1)
end

return ReaderSearch
