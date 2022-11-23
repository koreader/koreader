local Event = require("ui/event")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReaderMenuSearch = WidgetContainer:extend{
    kv = nil, -- key-value pairs for search results
    search_for = _("Help"),
}

function ReaderMenuSearch:init()
    if self.ui then
        self.ui.menu:registerToMainMenu(self)
    end
    -- todo: missing to restore the last search string
end

function ReaderMenuSearch:addToMainMenu(menu_items)
    menu_items.search_menu = {
        text = _("Menu Search"),
        callback = function()
            local search_dialog
            search_dialog = InputDialog:new{
                title = _("Search menu entry"),
                description = _("Search for a menu entry containing the following text (case insensitive)."),
                input = self.search_for,
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(search_dialog)
                            end,
                        },
                        {
                            text = _("OK"),
                            callback = function()
                                self.search_for = search_dialog:getInputText()
                                -- todo here we need the utf8tolower xxx
                                self.search_for = self.search_for:lower()
                                UIManager:close(search_dialog)
                                self:hereWeGo(self.search_for)
                            end,
                        },
                    }
                },
            }
            UIManager:show(search_dialog)
            search_dialog:onShowKeyboard()
        end,
        keep_menu_open = true,
    }
end

function ReaderMenuSearch:getCurrentSearchResults()
    local function cb(i)
        UIManager:close(self.kv)
        local path = TouchMenu.foundMenuItem[i][2]
        UIManager:sendEvent(Event:new("OpenMenu", path))
    end

    local kv_pairs = {}
    for i = 1, #TouchMenu.foundMenuItem do
        table.insert(kv_pairs, { TouchMenu.foundMenuItem[i][1],
                                 TouchMenu.foundMenuItem[i][3],
                                 callback = function() cb(i) end,
                               })
    end
    return kv_pairs
end

function ReaderMenuSearch:hereWeGo(search_string)
    UIManager:sendEvent(Event:new("MenuSearch", search_string))

    self.kv = KeyValuePage:new{
        title = _("Search results"),
        kv_pairs = self:getCurrentSearchResults()
    }
    UIManager:show(self.kv)
end

return ReaderMenuSearch
