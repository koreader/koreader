local CheckButton = require("ui/widget/checkbutton")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Utf8Proc = require("ffi/utf8proc")
local ffiUtil  = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local ReaderMenuSearch = WidgetContainer:extend{
    kv = nil, -- key-value pairs for search results
    search_for = nil,
}

function ReaderMenuSearch:init()
    if self.ui then
        self.ui.menu:registerToMainMenu(self)
    end
    -- todo: missing to restore the last search string
    self.search_for = G_reader_settings:readSetting("menu_search_string", _("Help"))
    self.animation_time_s = G_reader_settings:readSetting("menu_search_animation_time_s", 1.0)
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
                                G_reader_settings:saveSetting("menu_search_string", self.search_for)
                                UIManager:close(search_dialog)
                                self:hereWeGo(Utf8Proc.lowercase(self.search_for))
                            end,
                        },
                    }
                },
            }

            self.check_button_animation = CheckButton:new{
                text = _("Animation"),
                checked = self.animation_time_s ~= 0.0,
                parent = search_dialog,
                callback = function()
                    if self.animation_time_s == 0 then
                        self.animation_time_s = 1.0
                    else
                        self.animation_time_s = 0.0
                    end
                    G_reader_settings:saveSetting("menu_search_animation_time_s", self.animation_time_s)
                end,
            }
            search_dialog:addWidget(self.check_button_animation)

            UIManager:show(search_dialog)
            search_dialog:onShowKeyboard()
        end,
        keep_menu_open = true,
    }
end

function ReaderMenuSearch:getCurrentSearchResults()
    local function cb(i)
        self.kv:onClose()
        UIManager:setDirty(nil, "ui")

        local path = TouchMenu.foundMenuItem[i][2]
        UIManager:sendEvent(Event:new("OpenMenu", path, self.animation_time_s))
    end

    local kv_pairs = {}
    for i = 1, #TouchMenu.foundMenuItem do
        table.insert(kv_pairs, { TouchMenu.foundMenuItem[i][1],
                                 "", --TouchMenu.foundMenuItem[i][3],
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
