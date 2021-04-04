local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local BaseUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local FileSearcher = InputContainer:new{
    search_dialog = nil,

    --filesearcher
    -- state buffer
    dirs = {},
    files = {},
    results = {},
    items = 0,
    commands = nil,
}

function FileSearcher:readDir()
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    self.dirs = {self.path}
    self.files = {}
    while #self.dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for __, d in pairs(self.dirs) do
            -- handle files in d
            for f in lfs.dir(d) do
                local fullpath = d.."/"..f
                local attributes = lfs.attributes(fullpath) or {}
                -- Don't traverse hidden folders if we're not showing them
                if attributes.mode == "directory" and f ~= "." and f ~= ".." and (G_reader_settings:isTrue("show_hidden") or not util.stringStartsWith(f, ".")) then
                    table.insert(new_dirs, fullpath)
                    table.insert(self.files, {name = f, text = f.."/", attr = attributes, callback = function() FileManager:showFiles(fullpath) end})
                -- Always ignore macOS resource forks, too.
                elseif attributes.mode == "file" and not util.stringStartsWith(f, "._") and (show_unsupported or DocumentRegistry:hasProvider(fullpath)) then
                    table.insert(self.files, {name = f, text = f, attr = attributes, callback = function() ReaderUI:showReader(fullpath) end})
                end
            end
        end
        self.dirs = new_dirs
    end
end

function FileSearcher:setSearchResults()
    local keywords = self.search_value
    self.results = {}
    if keywords == "*" then -- one * to show all files
        self.results = self.files
    else
        for __,f in pairs(self.files) do
            if string.find(string.lower(f.name), string.lower(keywords)) and string.sub(f.name,-4) ~= ".sdr" then
                table.insert(self.results, f)
            end
        end
    end
    self.keywords = keywords
    self.items = #self.results
end

function FileSearcher:close()
    UIManager:close(self.search_dialog)
    self:readDir() --- @todo this probably doesn't need to be repeated once it's been done
    self:setSearchResults() --- @todo doesn't have to be repeated if the search term is the same
    if #self.results > 0 then
        self:showSearchResults()
    else
        UIManager:show(
            InfoMessage:new{
                text = BaseUtil.template(_("No results for '%1'."),
                                     self.search_value)
            }
        )
    end
end

function FileSearcher:onShowFileSearch()
    self.search_dialog = InputDialog:new{
        title = _("Enter filename to search for"),
        input = self.search_value,
        width = math.floor(Screen:getWidth() * 0.9),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    text = _("Home folder"),
                    enabled = G_reader_settings:has("home_dir"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == "" then return end
                        self.path = G_reader_settings:readSetting("home_dir")
                        self:close()
                    end,
                },
                {
                    text = _("Current folder"),
                    enabled = true,
                    is_enter_default = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == "" then return end
                        self.path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        self:close()
                    end,
                },
            },
        },
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function FileSearcher:showSearchResults()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
        height = Screen:getHeight() - (Size.margin.fullscreen_popout * 2),
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    table.sort(self.results, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:switchItemTable(_("Search results"), self.results)
    UIManager:show(menu_container)
end

return FileSearcher
