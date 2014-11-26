local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local DocumentRegistry = require("document/documentregistry")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local util = require("ffi/util")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")

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
    DEBUG("self.path", self.path)
    self.files = {}
    while #self.dirs ~= 0 do
        new_dirs = {}
        -- handle each dir
        for __, d in pairs(self.dirs) do
            -- handle files in d
            for f in lfs.dir(d) do
                local fullpath = d.."/"..f
                local attributes = lfs.attributes(fullpath)
                if attributes.mode == "directory" and f ~= "." and f~=".." then
                    table.insert(new_dirs, d.."/"..f)
                elseif attributes.mode == "file" and DocumentRegistry:getProvider(fullpath) then
                    table.insert(self.files, {name = f, path = fullpath, attr = attributes})
                end
            end
        end
        self.dirs = new_dirs
    end
end

function FileSearcher:setSearchResults()
    local ReaderUI = require("apps/reader/readerui")
    local keywords = self.search_value
    --DEBUG("self.files", self.files)
    self.results = {}
    if keywords == " " then -- one space to show all files
        self.results = self.files
    else
        for __,f in pairs(self.files) do
        DEBUG("f", f)
            if string.find(string.lower(f.name), string.lower(keywords)) then
                f.text = f.name
                f.name = nil
                f.callback = function()
                    ReaderUI:showReader(f.path)
                end
                table.insert(self.results, f)
            end
        end
    end
    --DEBUG("self.results", self.results)
    self.keywords = keywords
    self.items = #self.results
end

function FileSearcher:init(search_path)
    self.path = search_path or lfs.currentdir()
    self:showSearch()
end

function FileSearcher:close()
    if self.search_value then
        self.search_dialog:onClose()
        UIManager:close(self.search_dialog)
        if string.len(self.search_value) > 0 then
            self:readDir() -- TODO this probably doesn't need to be repeated once it's been done
            self:setSearchResults() -- TODO doesn't have to be repeated if the search term is the same
            if #self.results > 0 then
                self:showSearchResults() -- TODO something about no results
            else
                UIManager:show(
                    InfoMessage:new{
                        text = util.template(_("Found no files matching '%1'."), self.search_value)
                    }
                )
            end
        end
    end
end

function FileSearcher:showSearch()
    local dummy = self.search_value
    self.search_dialog = InputDialog:new{
        title = _("Search for books by filename"),             
        input = self.search_value,
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
                    text = _("Find books"),
                    enabled = true,
                    callback = function()
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
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.search_dialog:onShowKeyboard()
    UIManager:show(self.search_dialog)
end

function FileSearcher:showSearchResults()
    local ReaderUI = require("apps/reader/readerui")
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-15,
        height = Screen:getHeight()-15,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("cfont", 22),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    table.sort(self.results, function(v1,v2) return v1.text < v2.text end)
    self.search_menu:swithItemTable(_("Search Results"), self.results)
    UIManager:show(menu_container)
end

return FileSearcher
