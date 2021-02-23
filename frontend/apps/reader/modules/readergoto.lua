local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local SkimToWidget = require("ui/widget/skimtowidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderGoto = InputContainer:new{
    goto_menu_title = _("Go to page"),
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
    local curr_page
    if self.document.info.has_pages then
        curr_page = self.ui.paging.current_page
    else
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
        title = _("Enter page number"),
        input_hint = input_hint,
        description = self.document:hasHiddenFlows() and
            _([[
x for an absolute page number
[x] for a page number in the main (linear) flow
[x]y for a page number in the non-linear fragment y]])
            or nil,
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
                    text = _("Skim"),
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
                {
                    text = _("Go to page"),
                    enabled = true,
                    is_enter_default = true,
                    callback = function() self:gotoPage() end,
                }
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
    elseif self.ui.document:hasHiddenFlows() then
        -- if there are hidden flows, we accept the syntax [x]y
        -- for page number x in flow number y (y defaults to 0 if not present)
        local flow
        number, flow = string.match(page_number, "^ *%[(%d+)%](%d*) *$")
        flow = tonumber(flow) or 0
        number = tonumber(number)
        if number then
            if self.ui.document.flows[flow] ~= nil then
                if number < 1 or number > self.ui.document:getTotalPagesInFlow(flow) then
                    return
                end
                local page = 0
                -- in flow 0 (linear), we count pages skipping non-linear flows,
                -- in a non-linear flow the target page is immediate
                if flow == 0 then
                    for i=1, number do
                        page = self.ui.document:getNextPage(page)
                    end
                else
                    page = self.ui.document:getFirstPageInFlow(flow) + number - 1
                end
                if page > 0 then
                    self.ui:handleEvent(Event:new("GotoPage", page))
                    self:close()
                end
            end
        end
    end
end

function ReaderGoto:onGoToBeginning()
    local new_page = self.ui.document:getNextPage(0)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self.ui:handleEvent(Event:new("GotoPage", new_page))
    end
    return true
end

function ReaderGoto:onGoToEnd()
    local new_page = self.ui.document:getPrevPage(0)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self.ui:handleEvent(Event:new("GotoPage", new_page))
    end
    return true
end

return ReaderGoto
