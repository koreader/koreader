local Event = require("ui/event")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local SkimToWidget = require("ui/widget/skimtowidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
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
                    hold_callback = function()
                        if self.ui.doc_settings:has("pinned_page") then
                            local ConfirmBox = require("ui/widget/confirmbox")
                            UIManager:show(ConfirmBox:new{
                                text = _("Remove pinned page?"),
                                ok_text = _("Remove"),
                                ok_callback = function()
                                    self:close()
                                    self:onPinPage(nil, true)
                                end,
                            })
                        end
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
    local function make_geom(area)
        return area and Geom:new{ x = area.x, y = area.y, w = area.w, h = area.h }
    end
    local pn_or_xp = self.ui.doc_settings:readSetting("pinned_page")
    if pn_or_xp then
        local p_type = type(pn_or_xp)
        if (self.ui.rolling and p_type ~= "string") or
           (self.ui.paging and p_type == "string") then return true end -- page pinned in different engine
        self.ui.link:addCurrentLocationToStack()
        if self.ui.paging then
            if p_type == "number" then
                self.ui.paging:onGotoPage(pn_or_xp)
            else -- location, a table
                local new_page = pn_or_xp[1].page
                if bit.band(Screen:getRotationMode(), 1) ~= bit.band(pn_or_xp.rotation_mode, 1)
                    or self.ui.view.page_scroll ~= pn_or_xp.page_scroll
                    or self.document.configurable.text_wrap ~= pn_or_xp.text_wrap then
                    -- orientation, page/continuous or reflow mode changed, cannot restore exact location
                    self.ui.paging:onGotoPage(new_page)
                else
                    local loc = util.tableDeepCopy(pn_or_xp)
                    if self.ui.view.page_scroll then
                        for _, page_state in ipairs(loc) do
                            page_state.offset = make_geom(page_state.offset)
                            page_state.visible_area = make_geom(page_state.visible_area)
                            page_state.page_area = make_geom(page_state.page_area)
                        end
                    else
                        loc[1].offset = make_geom(loc[1].offset)
                        loc[2] = make_geom(loc[2]) -- visible area
                        loc[3] = make_geom(loc[3]) -- page area
                    end
                    if self.ui.paging.current_page == new_page then
                        self.ui.paging.current_page = 0
                    end
                    self.ui.paging:onRestoreBookLocation(loc)
                    self.ui.paging.visible_area = self.ui.view.visible_area
                end
            end
        else
            self.ui.rolling:onGotoXPointer(pn_or_xp)
        end
    end
    return true
end

function ReaderGoto:onPinPage(pageno, do_remove)
    local text, pn_or_xp
    if do_remove then
        text = _("Pinned page removed")
    else
        text = _("Page pinned")
        if self.ui.paging then
            if pageno then
                pn_or_xp = pageno
            else
                pn_or_xp = self.ui.paging:getBookLocation()
                pn_or_xp.rotation_mode = Screen:getRotationMode()
                pn_or_xp.text_wrap = self.document.configurable.text_wrap
                pn_or_xp.page_scroll = self.ui.view.page_scroll
            end
        else
            pn_or_xp = pageno and self.document:getPageXPointer(pageno) or self.document:getXPointer()
        end
    end
    self.ui.doc_settings:saveSetting("pinned_page", pn_or_xp)
    local Notification = require("ui/widget/notification")
    Notification:notify(text)
    return true
end

function ReaderGoto:getPinnedPageNumber()
    local pn_or_xp = self.ui.doc_settings:readSetting("pinned_page")
    if pn_or_xp then
        local p_type = type(pn_or_xp)
        if self.ui.paging then
            if p_type == "number" then
                return pn_or_xp
            elseif p_type == "table" then
                return pn_or_xp[1].page
            end
        elseif p_type == "string" then
            return self.document:getPageFromXPointer(pn_or_xp)
        end
    end
end

return ReaderGoto
