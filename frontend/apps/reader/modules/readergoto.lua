local Event = require("ui/event")
local InputDialog = require("ui/widget/inputdialog")
local SkimToWidget = require("ui/widget/skimtowidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderGoto = WidgetContainer:extend{}

function ReaderGoto:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderGoto:addToMainMenu(menu_items)
    menu_items.go_to = {
        text = _("Go to page"),
        callback = function()
            self:onShowGotoDialog()
        end,
    }
    menu_items.skim_to = {
        text = _("Skim document"),
        callback = function()
            self:onShowSkimtoDialog()
        end,
    }
end

function ReaderGoto:onShowGotoDialog()
    local curr_page = self.ui:getCurrentPage()
    local input_hint
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        input_hint = T("@%1 (%2 - %3)", self.ui.pagemap:getCurrentPageLabel(true),
                                        self.ui.pagemap:getFirstPageLabel(true),
                                        self.ui.pagemap:getLastPageLabel(true))
    else
        input_hint = T("@%1 (1 - %2)", curr_page, self.document:getPageCount())
    end
    input_hint = input_hint .. string.format("  %.2f%%", curr_page / self.document:getPageCount() * 100)
    self.goto_dialog = InputDialog:new{
        title = _("Enter page number or percentage"),
        input_hint = input_hint,
        input_type = "number",
        description = self.document:hasHiddenFlows() and
            _([[
x for an absolute page number
[x] for a page number in the main (linear) flow
[x]y for a page number in the non-linear fragment y]])
            or nil,
        buttons = {
            {
                {
                    text = _("Skim"),
                    callback = function()
                        self:close()
                        self:onShowSkimtoDialog()
                    end,
                },
                {
                    text = _("Go to %"),
                    callback = function()
                        self:gotoPercent()
                    end,
                }
            },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self:close()
                    end,
                },
                {
                    text = _("Go to page"),
                    is_enter_default = true,
                    callback = function()
                        self:gotoPage()
                    end,
                }
            },
        },
    }
    UIManager:show(self.goto_dialog)
    self.goto_dialog:onShowKeyboard()
end

function ReaderGoto:onShowSkimtoDialog()
    self.skimto = SkimToWidget:new{
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

function ReaderGoto:gotoPercent()
    local number = self.goto_dialog:getInputValue()
    if number then
        self.ui.link:addCurrentLocationToStack()
        self.ui:handleEvent(Event:new("GotoPercent", number))
        self:close()
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

function ReaderGoto:onGoToRandomPage()
    local page_count = self.document:getPageCount()
    if page_count == 1 then return true end
    local current_page = self.ui:getCurrentPage()
    if self.pages_pool == nil then
        self.pages_pool = {}
    end
    if #self.pages_pool == 0 or (#self.pages_pool == 1 and self.pages_pool[1] == current_page) then
        for i = 1, page_count do
            self.pages_pool[i] = i
        end
    end
    while true do
        local random_page_idx = math.random(1, #self.pages_pool)
        local random_page = self.pages_pool[random_page_idx]
        if random_page ~= current_page then
            table.remove(self.pages_pool, random_page_idx)
            self.ui.link:addCurrentLocationToStack()
            self.ui:handleEvent(Event:new("GotoPage", random_page))
            return true
        end
    end
end

return ReaderGoto
