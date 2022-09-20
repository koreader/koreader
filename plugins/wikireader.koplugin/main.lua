--[[--
This plugin reads wikipedia articles from the local storage.

@module koplugin.wikireader
--]]--

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WikiReaderWidget = dofile('./plugins/wikireader.koplugin/reader-widget.lua')
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local Device = require("device")
local util = require("util")

local _ = require("gettext")
local logger = require("logger")
local log = logger.dbg
local WikiReader = WidgetContainer:new{
    name = "wikireader",
    widget = nil
}

function WikiReader:init()
    self.ui.menu:registerToMainMenu(self)
end

local function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

function WikiReader:startInstance()
    -- Maybe a bit ugly with this global variable, but it works
    if WikiReaderInstance == nil then
        -- Add instance of this to self.ui
        log("START: starting with binding to ui")
        WikiReaderInstance = WikiReader:start()
    else
        local w = WikiReaderInstance.widget
        w:gotoTitle(w.history[#w.history])
        UIManager:show(InfoMessage:new{
            text = _("Re-opened WikiReader"),
            timeout = 5
        })
    end
end

function WikiReader:start()
    local wikireader_db_path = G_reader_settings:readSetting("wikireader_db_path")
    if wikireader_db_path == nil then
        UIManager:show(InfoMessage:new{
            text = _("Could not find database, set it in the plugin menu first"),
            timeout = 2
        })
    elseif wikireader_db_path:match('%.db$') == nil then
        UIManager:show(InfoMessage:new{
            text = _("Invalid database path (does not end in .db), please set it"),
            timeout = 2
        })
    else
        log("Got wikireader_db_path: ", wikireader_db_path)
        local db_file = wikireader_db_path
        if file_exists(db_file) then
            self.widget = WikiReaderWidget:new(db_file, "EPUB")
            return self
        else
            UIManager:show(InfoMessage:new{
                text = _("Did not find database at: ") .. db_file,
                timeout = 5
            })
        end
    end
end

function WikiReader:onSearchRequest ()
    local delay = 0.1
    if WikiReaderInstance == nil then 
        WikiReader:startInstance()
        delay = 1
    end

    UIManager:scheduleIn(delay, function()
        if WikiReaderInstance ~= nil then
            WikiReaderInstance.widget:showSearchBox()
        end
    end)
end

function WikiReader:showDBfilePicker()
    local home_dir = G_reader_settings:readSetting("home_dir") or Device.home_dir or "/"
    
    local path_chooser = PathChooser:new{
        title = _("Find and long press zim_articles.db"),
        select_directory = false,
        select_file = true,
        path = home_dir,
        onConfirm = function(path)
            G_reader_settings:saveSetting("wikireader_db_path", path)
            UIManager:show(InfoMessage:new{
                text = _("Set WikiReader database path to: ") .. path,
            })
        end
    }
    UIManager:show(path_chooser)

end

function WikiReader:getFavoritesTable ()
    local favorites_table = {{
        text = _("Add current page to favorites"),
        separator = true,
        callback = function(touchmenu_instance)
            if WikiReaderInstance == nil then 
                UIManager:show(InfoMessage:new{
                    text = "WikiReader is not openend",
                    timeout = 2
                })
            else
                WikiReaderInstance.widget:addCurrentTitleToFavorites()
            end
        end    
    }}

    local favorite_titles = G_reader_settings:readSetting("wikireader-favorites") or {}

    for i = 1, #favorite_titles do 
        local title = favorite_titles[i]
        table.insert(favorites_table, {
            text = title,
            callback = function()                
                local delay = 0.1
                if WikiReaderInstance == nil then 
                    WikiReader:startInstance()
                    delay = 1
                end
            
                UIManager:scheduleIn(delay, function()
                    if WikiReaderInstance ~= nil then
                        WikiReaderInstance.widget:gotoTitle(title)
                    end
                end)
            end
        })
    end
    log("Got favorites table:", favorites_table)
    return favorites_table
end



function WikiReader:addToMainMenu(menu_items)
    log("WIKI: Adding to menu: " .. _("WikiReader"))
    
    menu_items.wikireader = {
        text = _("WikiReader (Unstable)"),
        sorting_hint = "tools",
        {
            text = _("Open WikiReader"),
            callback = WikiReader.startInstance,
        },
        {
            text = _("Search WikiReader"),
            callback = WikiReader.onSearchRequest,
        },
        {
            text = _("Select database"),
            callback = WikiReader.showDBfilePicker,
        },
        {
            text = _("Favorites"),
            sub_item_table_func = function () return WikiReader:getFavoritesTable() end
        },
        {
            text = _("About"),
            callback = function ()
                UIManager:show(InfoMessage:new{
                    text = _("WikiReader allows KOReader to read an offline webpages database, most commonly for WikiPedia.\n" ..
                        "This database is a converted ZIM file, as it is used by for example the Kiwix software.\n\n" ..
                        "Build by Bart Grosman")
                })
            end
        }
    }
end
 

return WikiReader
