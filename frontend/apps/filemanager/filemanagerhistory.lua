local ButtonDialog = require("ui/widget/buttondialog")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local RenderText = require("ui/rendertext")
local Screen = require("device").screen
local _ = require("gettext")
local T = require("ffi/util").template

local FileManagerHistory = InputContainer:extend{
    hist_menu_title = _("History"),
}

function FileManagerHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerHistory:addToMainMenu(menu_items)
    -- insert table to main tab of filemanager menu
    menu_items.history = {
        text = self.hist_menu_title,
        callback = function()
            self:onShowHist()
        end,
    }
end

function FileManagerHistory:updateItemTable()
    self.hist_menu:switchItemTable(self.hist_menu_title,
                                  require("readhistory").hist)
end

function FileManagerHistory:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerHistory:onMenuHold(item)
    local font_size = Font:getFace("tfont")
    local text_remove_hist = _("Remove \"%1\" from history")
    local text_remove_without_item = T(text_remove_hist, "")
    local text_remove_hist_width = (RenderText:sizeUtf8Text(
        0, self.width, font_size, text_remove_without_item).x )
    local text_item_width = (RenderText:sizeUtf8Text(
        0, self.width , font_size, item.text).x )

    local item_trun
    if self.width < text_remove_hist_width + text_item_width then
        item_trun = RenderText:truncateTextByWidth(item.text, font_size, 1.2 * self.width - text_remove_hist_width)
    else
        item_trun = item.text
    end
    local text_remove = T(text_remove_hist, item_trun)

    self.histfile_dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = text_remove,
                    callback = function()
                        require("readhistory"):removeItem(item)
                        self._manager:updateItemTable()
                        UIManager:close(self.histfile_dialog)
                    end,
                },
            },
            {
                {
                    text = _("Book information"),
                    enabled = FileManagerBookInfo:isSupported(item.file),
                    callback = function()
                        FileManagerBookInfo:show(item.file)
                        UIManager:close(self.histfile_dialog)
                    end,
                 },
            },
            {},
            {
                {
                    text = _("Clear history of deleted files"),
                    callback = function()
                        require("readhistory"):clearMissing()
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
    self.hist_menu = Menu:new{
        ui = self.ui,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        onMenuHold = self.onMenuHold,
        _manager = self,
    }
    self:updateItemTable()
    self.hist_menu.close_callback = function()
        -- Close it at next tick so it stays displayed
        -- while a book is opening (avoids a transient
        -- display of the underlying File Browser)
        UIManager:nextTick(function()
            UIManager:close(self.hist_menu)
        end)
    end
    UIManager:show(self.hist_menu)
    return true
end

return FileManagerHistory
