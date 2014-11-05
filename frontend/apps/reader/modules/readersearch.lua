local InputContainer = require("ui/widget/container/inputcontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderSearch = InputContainer:new{
    direction = 0, -- 0 for search forward, 1 for search backward
    case_insensitive = 1, -- default to case insensitive
}

function ReaderSearch:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderSearch:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Fulltext search"),
        tap_input = {
            title = _("Input text to search for"),
            type = "text",
            callback = function(input)
                self:onShowSearchDialog(input)
            end,
        },
    })
end

function ReaderSearch:onShowSearchDialog(text)
    local do_search = function(search_func, text, param)
        return function()
            local res = search_func(self, text, param)
            if res then
                self.ui.link:onGotoLink(res[1].start)
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
            DEBUG("highlight clear")
            self.ui.highlight:clear()
        end,
    }
    local res = do_search(self.searchFromCurrent, text, 0)()
    UIManager:show(self.search_dialog)
    UIManager:setDirty(self.dialog, "partial")
    return true
end

function ReaderSearch:search(pattern, origin)
    local direction = self.direction
    local case = self.case_insensitive
    return self.ui.document:findText(pattern, origin, direction, case)
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
