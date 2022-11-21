local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local SortWidget = require("ui/widget/sortwidget")
local TouchMenu = require("ui/widget/touchmenu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffi = require("ffi")
local C = ffi.C
local ffiUtil  = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util  = require("util")
local _ = require("gettext")
local Input = Device.input
local T = ffiUtil.template

local ReaderMenuSearch = WidgetContainer:extend{
    kv = nil, -- key-value pairs for search results

}

function ReaderMenuSearch:init()
    if self.ui then
        self.ui.menu:registerToMainMenu(self)
    end
end

function ReaderMenuSearch:addToMainMenu(menu_items)
    menu_items.search_menu = {
        text = _("Menu Search"),
        callback = function()
            local search_dialog
            search_dialog = InputDialog:new{
                title = _("Search menu entry"),
                input = "Buchtitel", --xxx change this
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
                                local search_string = (search_dialog:getInputText())
                                search_string = search_string:lower() -- here we need the ugly utf8tolower todo xxx
                                UIManager:close(search_dialog)
                                self:hereWeGo(search_string)
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
        print("xxxxxxxx cb(i)", i)
        local path = TouchMenu.foundMenuItem[i][2]
        print("xxxxxxxx path", path)
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
    print("xxx search_string", search_string)

    UIManager:sendEvent(Event:new("MenuSearch", search_string))
        -- here comes a keyValuePage thing to select a menu item in the form "tap-1level-2level3-leve" with ellipsis and a hold to show all :)
--            print("xxx", TouchMenu.foundMenuItem[2][1])
--            TouchMenu:openMenuAt(TouchMenu.foundMenuItem[2][1])

    self.kv = KeyValuePage:new{
        title = _("Search results"),
        kv_pairs = self:getCurrentSearchResults()
    }
    UIManager:show(self.kv)



    local path = "3.10.sub_item_table.17.text_func"
    UIManager:sendEvent(Event:new("OpenMenu", path))
end



return ReaderMenuSearch
