local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local DocSettings = require("docsettings")
local Menu = require("ui/widget/menu")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")

local history_dir = "./history/"

local FileManagerHistory = InputContainer:extend{
    hist_menu_title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuHold(item)
    self.histfile_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("Delete"),
                    callback = function()
                        os.remove(history_dir..item.histfile)
                        self._manager:updateItemTable()
                        UIManager:close(self.histfile_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.histfile_dialog)
    return true
end

function FileManagerHistory:onShowHist()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }

    self.hist_menu = Menu:new{
        ui = self.ui,
        width = Screen:getWidth()-50,
        height = Screen:getHeight()-50,
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        _manager = self,
    }
    self:updateItemTable()

    table.insert(menu_container, self.hist_menu)

    self.hist_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    UIManager:show(menu_container)
    return true
end

function FileManagerHistory:addToMainMenu(tab_item_table)
    -- insert table to info tab of filemanager menu
    table.insert(tab_item_table.info, {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    })
end

function FileManagerHistory:updateItemTable()
    self.hist = {}

    for f in lfs.dir(history_dir) do
        local path = history_dir..f
        if lfs.attributes(path, "mode") == "file" then
            local name = DocSettings:getNameFromHistory(f)
            table.insert(self.hist, {
                date = lfs.attributes(path, "modification"),
                text = name,
                histfile = f,
                callback = function()
                    ReaderUI:showReader(
                        DocSettings:getPathFromHistory(f).. "/" .. name)
                end
            })
        end
    end
    table.sort(self.hist, function(v1, v2) return v1.date > v2.date end)

    self.hist_menu:swithItemTable(self.hist_menu_title, self.hist)
end

return FileManagerHistory
