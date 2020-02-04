local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
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

    --filemanagersearch
    use_previous_search_results = false,
    lastsearch = nil,
}

function FileSearcher:readDir()
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
                    table.insert(self.files, {name = f, path = fullpath, attr = attributes})
                -- Always ignore macOS resource forks, too.
                elseif attributes.mode == "file" and not util.stringStartsWith(f, "._") and DocumentRegistry:hasProvider(fullpath) then
                    table.insert(self.files, {name = f, path = fullpath, attr = attributes})
                end
            end
        end
        self.dirs = new_dirs
    end
end

function FileSearcher:setSearchResults()
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local keywords = self.search_value
    self.results = {}
    if keywords == " " then -- one space to show all files
        self.results = self.files
    else
        for __,f in pairs(self.files) do
            if string.find(string.lower(f.name), string.lower(keywords)) and string.sub(f.name,-4) ~= ".sdr" then
                if f.attr.mode == "directory" then
                    f.text = f.name.."/"
                    f.name = nil
                    f.callback = function()
                        FileManager:showFiles(f.path)
                    end
                    table.insert(self.results, f)
                else
                    f.text = f.name
                    f.name = nil
                    f.callback = function()
                        ReaderUI:showReader(f.path)
                    end
                    table.insert(self.results, f)
                end
            end
        end
    end
    self.keywords = keywords
    self.items = #self.results
end

function FileSearcher:close()
    if self.search_value then
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 then
            self:readDir() --- @todo this probably doesn't need to be repeated once it's been done
            self:setSearchResults() --- @todo doesn't have to be repeated if the search term is the same
            if #self.results > 0 then
                self:showSearchResults() --- @todo something about no results
            else
                UIManager:show(
                    InfoMessage:new{
                        text = BaseUtil.template(_("Found no files matching '%1'."),
                                             self.search_value)
                    }
                )
            end
        end
    end
end

function FileSearcher:onShowFileSearch(search_path)
    local dummy = self.search_value
    local enabled_search_home_dir = true
    if not G_reader_settings:readSetting("home_dir") then
        enabled_search_home_dir = false
    end
    self.search_dialog = InputDialog:new{
        title = _("Search for books by filename"),
        input = self.search_value,
        width = Screen:getWidth() * 0.9,
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
                    text = _("Current folder"),
                    enabled = true,
                    callback = function()
                        self.path = search_path or lfs.currentdir()
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == dummy then -- probably DELETE this if/else block
                            self.use_previous_search_results = true
                        else
                            self.use_previous_search_results = false
                        end
                        self:close()
                    end,
                },
                {
                    text = _("Home folder"),
                    enabled = enabled_search_home_dir,
                    callback = function()
                        self.path = G_reader_settings:readSetting("home_dir")
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == dummy then -- probably DELETE this if/else block
                            self.use_previous_search_results = true
                        else
                            self.use_previous_search_results = false
                        end
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
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        perpage = G_reader_settings:readSetting("items_per_page") or 14,
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    table.sort(self.results, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:switchItemTable(_("Search Results"), self.results)
    UIManager:show(menu_container)
end

return FileSearcher
