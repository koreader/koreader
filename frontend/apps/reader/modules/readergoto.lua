local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local SkimToWidget = require("apps/reader/skimtowidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderGoto = InputContainer:new{
    goto_menu_title = _("Go to"),
    skim_menu_title = _("Skim document"),
}

function ReaderGoto:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderGoto:addToMainMenu(menu_items)
    -- insert goto command to main reader menu
    menu_items.go_to = {
        text = self.goto_menu_title,
        callback = function()
            self:onShowGotoDialog()
        end,
    }
    menu_items.skim_to = {
        text = self.skim_menu_title,
        callback = function()
            self:onShowSkimtoDialog()
        end,
    }
end

function ReaderGoto:onShowGotoDialog()
    local dialog_title, goto_btn, curr_page
    if self.document.info.has_pages then
        dialog_title = _("Go to Page")
        goto_btn = {
            is_enter_default = true,
            text = _("Page"),
            callback = function() self:gotoPage() end,
        }
        curr_page = self.ui.paging.current_page
    else
        dialog_title = _("Go to Location")
        goto_btn = {
            is_enter_default = true,
            text = _("Location"),
            callback = function() self:gotoPage() end,
        }
        -- only CreDocument has this method
        curr_page = self.document:getCurrentPage()
    end
    local input_hint
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        input_hint = T("@%1 (%2 - %3)", self.ui.pagemap:getCurrentPageLabel(true),
                                        self.ui.pagemap:getFirstPageLabel(true),
                                        self.ui.pagemap:getLastPageLabel(true))
    else
        input_hint = T("@%1 (1 - %2)", curr_page, self.document:getPageCount())
    end
    self.goto_dialog = InputDialog:new{
        title = dialog_title,
        input_hint = input_hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:close()
                    end,
                },
                {
                    text = _("Skim mode"),
                    enabled = true,
                    callback = function()
                        self:close()
                        self.skimto = SkimToWidget:new{
                            document = self.document,
                            ui = self.ui,
                            callback_switch_to_goto = function()
                                UIManager:close(self.skimto)
                                self:onShowGotoDialog()
                            end,
                        }
                        UIManager:show(self.skimto)

                    end,
                },
                goto_btn,
            },
        },
        input_type = "number",
    }
    UIManager:show(self.goto_dialog)
    self.goto_dialog:onShowKeyboard()
end

function ReaderGoto:onShowSkimtoDialog()
    self.skimto = SkimToWidget:new{
        document = self.document,
        ui = self.ui,
        callback_switch_to_goto = function()
            UIManager:close(self.skimto)
            self:onShowGotoDialog()
        end,
    }
    UIManager:show(self.skimto)
end

function ReaderGoto:close()
    UIManager:close(self.goto_dialog)
end

function ReaderGoto:gotoPage()
    local page_number = self.goto_dialog:getInputText()
    local relative_sign = page_number:sub(1, 1)
    local number = tonumber(page_number)
    if number then
        self.ui.link:addCurrentLocationToStack()
        if relative_sign == "+" or relative_sign == "-" then
            self.ui:handleEvent(Event:new("GotoRelativePage", number))
        else
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                number = self.ui.pagemap:getRenderedPageNumber(page_number, true)
                if number then -- found
                    self.ui:handleEvent(Event:new("GotoPage", number))
                else
                    return -- avoid self:close()
                end
            else
                self.ui:handleEvent(Event:new("GotoPage", number))
            end
        end
        self:close()
    end
end

function ReaderGoto:onGoToBeginning()
    self.ui.link:addCurrentLocationToStack()
    self.ui:handleEvent(Event:new("GotoPage", 1))
    return true
end

function ReaderGoto:onGoToEnd()
    local endpage = self.document:getPageCount()
    if endpage then
        self.ui.link:addCurrentLocationToStack()
        self.ui:handleEvent(Event:new("GotoPage", endpage))
    end
    return true
end

return ReaderGoto
