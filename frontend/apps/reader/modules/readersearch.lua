local ButtonDialog = require("ui/widget/buttondialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local ReaderSearch = InputContainer:new{
    direction = 0, -- 0 for search forward, 1 for search backward
    case_insensitive = true, -- default to case insensitive
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderSearch:addToMainMenu(menu_items)
    menu_items.fulltext_search = {
        text = _("Fulltext search"),
        tap_input = {
            title = _("Input text to search for"),
            ok_text = _("Search all text"),
            type = "text",
            callback = function(input)
                self:onShowSearchDialog(input)
            end,
        },
    }
end

function ReaderSearch:onShowSearchDialog(text)
    local do_search = function(search_func, _text, param)
        return function()
            local res = search_func(self, _text, param)
            if res then
                if self.ui.document.info.has_pages then
                    self.ui.link:onGotoLink({page = res.page - 1})
                    self.view.highlight.temp[res.page] = res
                else
                    self.ui.link:onGotoLink(res[1].start)
                end
            end
        end
    end
    self.search_dialog = ButtonDialog:new{
        alpha = 0.5,
        buttons = {
            {
                {
                    text = "|<",
                    callback = do_search(self.searchFromStart, text),
                },
                {
                    text = "<",
                    callback = do_search(self.searchNext, text, 1),
                },
                {
                    text = ">",
                    callback = do_search(self.searchNext, text, 0),
                },
                {
                    text = ">|",
                    callback = do_search(self.searchFromEnd, text),
                },
            }
        },
        tap_close_callback = function()
            logger.dbg("highlight clear")
            self.ui.highlight:clear()
        end,
    }
    do_search(self.searchFromCurrent, text, 0)()
    UIManager:show(self.search_dialog)
    -- TODO: regional
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
    return self:search(pattern, -1)
end

function ReaderSearch:searchFromEnd(pattern)
    self.direction = 1
    return self:search(pattern, -1)
end

function ReaderSearch:searchFromCurrent(pattern, direction)
    self.direction = direction
    return self:search(pattern, 0)
end

-- ignore current page and search next occurrence
function ReaderSearch:searchNext(pattern, direction)
    self.direction = direction
    return self:search(pattern, 1)
end

return ReaderSearch
