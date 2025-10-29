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
                    text = _("Pin current page"),
                    callback = function()
                        self:close()
                        self:onPinPage()
                    end,
                },
                {
                    text = _("Go to pinned page"),
                    enabled_func = function()
                        return self.ui.doc_settings:has("pinned_page")
                    end,
                    callback = function()
                        self:close()
                        self:onGoToPinnedPage()
                    end,
                },
            },
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
                },
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
                },
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
    if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
        local label = self.ui.pagemap:cleanPageLabel(page_number)
        local _, pn = self.ui.pagemap:getPageLabelProps(label)
        if pn then
            self:close()
            self.ui:handleEvent(Event:new("GotoPage", pn))
        end
        return
    end
    local relative_sign = page_number:sub(1, 1)
    local number = tonumber(page_number)
    if number then
        self.ui.link:addCurrentLocationToStack()
        if relative_sign == "+" or relative_sign == "-" then
            self.ui:handleEvent(Event:new("GotoRelativePage", number))
        else
            self.ui:handleEvent(Event:new("GotoPage", number))
        end
        self:close()
    elseif self.document:hasHiddenFlows() then
        -- if there are hidden flows, we accept the syntax [x]y
        -- for page number x in flow number y (y defaults to 0 if not present)
        local flow
        number, flow = string.match(page_number, "^ *%[(%d+)%](%d*) *$")
        flow = tonumber(flow) or 0
        number = tonumber(number)
        if number then
            if self.document.flows[flow] ~= nil then
                if number < 1 or number > self.document:getTotalPagesInFlow(flow) then
                    return
                end
                local page = 0
                -- in flow 0 (linear), we count pages skipping non-linear flows,
                -- in a non-linear flow the target page is immediate
                if flow == 0 then
                    for i=1, number do
                        page = self.document:getNextPage(page)
                    end
                else
                    page = self.document:getFirstPageInFlow(flow) + number - 1
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
    local new_page = self.document:getNextPage(0)
    if new_page then
        self.ui.link:addCurrentLocationToStack()
        self.ui:handleEvent(Event:new("GotoPage", new_page))
    end
    return true
end

function ReaderGoto:onGoToEnd()
    local new_page = self.document:getPrevPage(0)
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

function ReaderGoto:onGoToPinnedPage()
    local pn_or_xp = self.ui.doc_settings:readSetting("pinned_page")
    if pn_or_xp then
        self.ui.link:addCurrentLocationToStack()
        if self.ui.paging then
            self.ui.paging:onGotoPage(pn_or_xp)
        else
            self.ui.rolling:onGotoXPointer(pn_or_xp)
        end
    end
    return true
end

function ReaderGoto:onPinPage(pageno)
    local pn_or_xp
    if pageno then
        pn_or_xp = self.ui.paging and pageno or self.document:getPageXPointer(pageno)
    else -- current page
        pn_or_xp = self.ui.paging and self.view.state.page or self.document:getXPointer()
    end
    self.ui.doc_settings:saveSetting("pinned_page", pn_or_xp)
    local Notification = require("ui/widget/notification")
    Notification:notify(_("Page pinned"))
    return true
end

function ReaderGoto:getPinnedPageNumber()
    local pn_or_xp = self.ui.doc_settings:readSetting("pinned_page")
    if pn_or_xp then
        return self.ui.paging and pn_or_xp or self.document:getPageFromXPointer(pn_or_xp)
    end
end

return ReaderGoto
