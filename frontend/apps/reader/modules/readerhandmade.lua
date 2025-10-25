local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderHandMade = WidgetContainer:extend{
    custom_toc_symbol = "\u{EAEC}", -- used in a few places
}

function ReaderHandMade:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderHandMade:onReadSettings(config)
    self.toc_enabled = config:isTrue("handmade_toc_enabled")
    self.toc_edit_enabled = config:nilOrTrue("handmade_toc_edit_enabled")
    self.toc = config:readSetting("handmade_toc") or {}
    self.flows_enabled = config:isTrue("handmade_flows_enabled")
    self.flows_edit_enabled = config:nilOrTrue("handmade_flows_edit_enabled")
    self.flow_points = config:readSetting("handmade_flow_points") or {}
    self.inactive_flow_points = {}

    -- Don't mess toc and flow_points made on that document if saved when
    -- we were using a different engine - backup them if that's the case.
    if #self.toc > 0 then
        local has_xpointers = self.toc[1].xpointer ~= nil
        if self.ui.rolling and not has_xpointers then
            config:saveSetting("handmade_toc_paging", self.toc)
            self.toc = config:readSetting("handmade_toc_rolling") or {}
            config:delSetting("handmade_toc_rolling")
        elseif self.ui.paging and has_xpointers then
            config:saveSetting("handmade_toc_rolling", self.toc)
            self.toc = config:readSetting("handmade_toc_paging") or {}
            config:delSetting("handmade_toc_paging")
        end
    else
        if self.ui.rolling and config:has("handmade_toc_rolling") then
            self.toc = config:readSetting("handmade_toc_rolling")
            config:delSetting("handmade_toc_rolling")
        elseif self.ui.paging and config:has("handmade_toc_paging") then
            self.toc = config:readSetting("handmade_toc_paging")
            config:delSetting("handmade_toc_paging")
        end
    end
    if #self.flow_points > 0 then
        local has_xpointers = self.flow_points[1].xpointer ~= nil
        if self.ui.rolling and not has_xpointers then
            config:saveSetting("handmade_flow_points_paging", self.flow_points)
            self.flow_points = config:readSetting("handmade_flow_points_rolling") or {}
            config:delSetting("handmade_flow_points_rolling")
        elseif self.ui.paging and has_xpointers then
            config:saveSetting("handmade_flow_points_rolling", self.flow_points)
            self.flow_points = config:readSetting("handmade_flow_points_paging") or {}
            config:delSetting("handmade_flow_points_paging")
        end
    else
        if self.ui.rolling and config:has("handmade_flow_points_rolling") then
            self.flow_points = config:readSetting("handmade_flow_points_rolling")
            config:delSetting("handmade_flow_points_rolling")
        elseif self.ui.paging and config:has("handmade_flow_points_paging") then
            self.flow_points = config:readSetting("handmade_flow_points_paging")
            config:delSetting("handmade_flow_points_paging")
        end
    end
end

function ReaderHandMade:onSaveSettings()
    self.ui.doc_settings:saveSetting("handmade_toc_enabled", self.toc_enabled)
    self.ui.doc_settings:saveSetting("handmade_toc_edit_enabled", self.toc_edit_enabled)
    if #self.toc > 0 then
        self.ui.doc_settings:saveSetting("handmade_toc", self.toc)
    else
        self.ui.doc_settings:delSetting("handmade_toc")
    end
    self.ui.doc_settings:saveSetting("handmade_flows_enabled", self.flows_enabled)
    self.ui.doc_settings:saveSetting("handmade_flows_edit_enabled", self.flows_edit_enabled)
    if #self.flow_points > 0 then
        self.ui.doc_settings:saveSetting("handmade_flow_points", self.flow_points)
    else
        self.ui.doc_settings:delSetting("handmade_flow_points")
    end
end

function ReaderHandMade:isHandmadeTocEnabled()
    return self.toc_enabled
end

function ReaderHandMade:isHandmadeTocEditEnabled()
    return self.toc_edit_enabled
end

function ReaderHandMade:isHandmadeHiddenFlowsEnabled()
    -- Even if currently empty, we return true, which allows showing '//' in
    -- the footer and let know hidden flows are enabled.
    return self.flows_enabled
end

function ReaderHandMade:isHandmadeHiddenFlowsEditEnabled()
    return self.flows_edit_enabled
end

function ReaderHandMade:onToggleHandmadeToc()
    self.toc_enabled = not self.toc_enabled
    self:setupToc()
    -- Have footer updated, so we may see this took effect
    self.view.footer:maybeUpdateFooter()
end

function ReaderHandMade:onToggleHandmadeFlows()
    self.flows_enabled = not self.flows_enabled
    self:setupFlows()
    -- Have footer updated, so we may see this took effect
    self.view.footer:maybeUpdateFooter()
    self.ui.annotation:setNeedsUpdateFlag()
end

function ReaderHandMade:addToMainMenu(menu_items)
    if not Device:isTouchDevice() and not Device:useDPadAsActionKeys() then
        -- As it's currently impossible to create custom hidden flows on non-touch devices without useDPadAsActionKeys,
        -- (technically speaking, without a 'hold' or 'long-press' event) and really impractical to create a custom toc,
        -- it's better hide these features completely for now.
        return
    end
    menu_items.handmade_toc = {
        text = _("Custom table of contents") .. " " .. self.custom_toc_symbol,
        checked_func = function() return self.toc_enabled end,
        callback = function()
            self:onToggleHandmadeToc()
        end,
    }
    menu_items.handmade_hidden_flows = {
        text = _("Custom hidden flows"),
        checked_func = function() return self.flows_enabled end,
        callback = function()
            self:onToggleHandmadeFlows()
        end,
    }
    --[[ Not yet implemented
    menu_items.handmade_page_numbers = {
        text = _("Custom page numbers"),
        checked_func = function() return false end,
        callback = function()
        end,
    }
    ]]--
    menu_items.handmade_settings = {
        text = _("Custom layout features"),
        sub_item_table_func = function()
            return {
                {
                    text = _("About custom table of contents") .. " " .. self.custom_toc_symbol,
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _([[
If the book has no table of contents or you would like to substitute it with your own, you can create a custom TOC. The original TOC (if available) will not be altered.

You can create, edit and remove chapters:
- in Page browser, by long-pressing on a thumbnail;
- on a book page, by selecting some text to be used as the chapter title.
(Once you're done building it and don't want to see the buttons anymore, you can disable Edit mode.)

This custom table of contents is currently limited to a single level and can't have sub-chapters.]])
                        })
                    end,
                    keep_menu_open = true,
                },
                {
                    text = _("Edit mode"),
                    enabled_func = function()
                        return self:isHandmadeTocEnabled()
                    end,
                    checked_func = function()
                        return self:isHandmadeTocEditEnabled()
                    end,
                    callback = function()
                        self.toc_edit_enabled = not self.toc_edit_enabled
                        self:updateHighlightDialog()
                    end,
                },
                --[[ Not yet implemented
                {
                    text = _("Add multiple chapter start page numbers"),
                },
                ]]--
                {
                    text = _("Clear custom table of contents"),
                    enabled_func = function()
                        return #self.toc > 0
                    end,
                    callback = function(touchmenu_instance)
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to clear your custom table of contents?"),
                            ok_callback = function()
                                self.toc = {}
                                self.ui:handleEvent(Event:new("UpdateToc"))
                                -- The footer may be visible, so have it update its chapter related items
                                self.view.footer:maybeUpdateFooter()
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end,
                        })
                    end,
                    keep_menu_open = true,
                    separator = true,
                },
                {
                    text = _("About custom hidden flows"),
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _([[
Custom hidden flows can be created to exclude sections of the book from your normal reading flow:
- hidden flows will automatically be skipped when turning pages within the regular flow;
- pages part of hidden flows are assigned distinct page numbers and won't be considered in the various book & chapter progress and time to read features;
- following direct links to pages in hidden flows will still work, including from the TOC or Book map.

This can be useful to exclude long footnotes or bibliography sections.
It can also be handy when interested in reading only a subset of a book.

In Page browser, you can long-press on a thumbnail to start a hidden flow or restart the regular flow on this page.
(Once you're done building it and don't want to see the button anymore, you can disable Edit mode.)

Hidden flows are shown with gray or hatched background in Book map and Page browser.]])
                        })
                    end,
                    keep_menu_open = true,
                },
                {
                    text = _("Edit mode"),
                    enabled_func = function()
                        return self:isHandmadeHiddenFlowsEnabled()
                    end,
                    checked_func = function()
                        return self:isHandmadeHiddenFlowsEditEnabled()
                    end,
                    callback = function()
                        self.flows_edit_enabled = not self.flows_edit_enabled
                    end,
                },
                {
                    text_func = function()
                        return T(_("Clear inactive marked pages (%1)"), #self.inactive_flow_points)
                    end,
                    enabled_func = function()
                        return #self.inactive_flow_points > 0
                    end,
                    callback = function(touchmenu_instance)
                        UIManager:show(ConfirmBox:new{
                            text = _("Inactive marked pages are pages that you tagged as start hidden flow or restart regular flow, but that other marked pages made them have no effect.\nAre you sure you want to clear them?"),
                            ok_callback = function()
                                for i=#self.inactive_flow_points, 1, -1 do
                                    table.remove(self.flow_points, self.inactive_flow_points[i])
                                end
                                self:updateDocFlows()
                                self.ui:handleEvent(Event:new("UpdateToc"))
                                self.ui:handleEvent(Event:new("InitScrollPageStates"))
                                -- The footer may be visible, so have it update its dependent items
                                self.view.footer:maybeUpdateFooter()
                                self.ui.annotation:setNeedsUpdateFlag()
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end,
                        })
                    end,
                    keep_menu_open = true,
                },
                {
                    text = _("Clear all marked pages"),
                    enabled_func = function()
                        return #self.flow_points > 0
                    end,
                    callback = function(touchmenu_instance)
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to clear all your custom hidden flows?"),
                            ok_callback = function()
                                self.flow_points = {}
                                self:updateDocFlows()
                                self.ui:handleEvent(Event:new("UpdateToc"))
                                self.ui:handleEvent(Event:new("InitScrollPageStates"))
                                -- The footer may be visible, so have it update its dependent items
                                self.view.footer:maybeUpdateFooter()
                                self.ui.annotation:setNeedsUpdateFlag()
                                if touchmenu_instance then
                                    touchmenu_instance:updateItems()
                                end
                            end,
                        })
                    end,
                    keep_menu_open = true,
                    separator = true,
                },
                --[[ Not yet implemented
                {
                    text = _("About custom page numbers"),
                },
                {
                    text = _("Clear custom page numbers"),
                },
                ]]--
            }
        end,
    }
end

function ReaderHandMade:updateHandmagePages()
    if not self.ui.rolling then
        return
    end
    for _, item in ipairs(self.toc) do
        item.page = self.document:getPageFromXPointer(item.xpointer)
    end
    for _, item in ipairs(self.flow_points) do
        item.page = self.document:getPageFromXPointer(item.xpointer)
    end
end

function ReaderHandMade:onReaderReady()
    -- Called on load, and with a CRE document when reloading after partial rerendering.
    -- Notes:
    -- - ReaderFooter (from ReaderView) will have its onReaderReady() called before ours,
    --   and it may fillToc(). So, it may happen that the expensive validateAndFixToc()
    --   is called twice (first with the original ToC, then with ours).
    -- - ReaderRolling will have its onReaderReady() called after ours, and if we
    --   have set up hidden flows, we'll have overridden some documents methods so
    --   its cacheFlows() is a no-op.
    self:updateHandmagePages()
    -- Don't have each of these send their own events: we'll send them once afterwards
    self:setupFlows(true)
    self:setupToc(true)
    -- Now send the events
    if self.toc_enabled or self.flows_enabled then
        self.ui:handleEvent(Event:new("UpdateToc"))
    end
    if self.flows_enabled then
        -- Needed to skip hidden flows if PDF in scroll mode
        self.ui:handleEvent(Event:new("InitScrollPageStates"))
    end
end

function ReaderHandMade:onDocumentRerendered()
    -- Called with CRE document when partial rerendering not enabled
    self:updateHandmagePages()
    -- Don't have these send events their own events
    self:setupFlows(true)
    self:setupToc(true)
    -- ReaderToc will process this event just after us, and will
    -- call its onUpdateToc: we don't need to send it.
    -- (Also, no need for InitScrollPageStates with CRE.)
end

function ReaderHandMade:setupToc(no_event)
    if self.toc_enabled then
        -- If enabled, plug one method into the document object,
        -- so it is used instead of the method from its class.
        self.document.getToc = function(this)
            -- ReaderToc may add fields to ToC items: return a copy,
            -- so the one we will save doesn't get polluted.
            return util.tableDeepCopy(self.toc)
        end
    else
        -- If disabled, remove our plug so the method from the
        -- class gets used again.
        self.document.getToc = nil
    end
    self:updateHighlightDialog()
    if not no_event then
        self.ui:handleEvent(Event:new("UpdateToc"))
    end
end

function ReaderHandMade:updateHighlightDialog()
    if self.toc_enabled and self.toc_edit_enabled then
        -- We don't want this button to be the last wide one, and rather
        -- keep having the Search button being that one: so plug this one
        -- just before 12_search.
        self.ui.highlight:addToHighlightDialog("12_0_make_handmade_toc_item", function(this)
            return {
                text_func = function()
                    local selected_text = this.selected_text
                    local pageno, xpointer
                    if self.ui.rolling then
                        xpointer = selected_text.pos0
                    else
                        pageno = selected_text.pos0.page
                    end
                    local text
                    if self:hasPageTocItem(pageno, xpointer) then
                        text = _("Edit TOC chapter")
                    else
                        text = _("Start TOC chapter")
                    end
                    text = text .. " " .. self.custom_toc_symbol
                    return text
                end,
                callback = function()
                    local selected_text = this.selected_text
                    this:onClose()
                    self:addOrEditPageTocItem(nil, nil, selected_text)
                end,
                hold_callback = function() -- no dialog: directly creates new TOC item with selection (if none existing)
                    local selected_text = this.selected_text
                    this:onClose()
                    self:addOrEditPageTocItem(nil, nil, selected_text, true)
               end,
            }
        end)
    else
        self.ui.highlight:removeFromHighlightDialog("12_0_make_handmade_toc_item")
    end
end

function ReaderHandMade:_getItemIndex(tab, pageno, xpointer)
    if not pageno and xpointer then
        pageno = self.document:getPageFromXPointer(xpointer)
    end
    -- (No need to use a binary search, our user made tables should
    -- not be too large)
    local matching_idx
    local insertion_idx = #tab + 1
    for i, item in ipairs(tab) do
        if item.page >= pageno then
            if item.page > pageno then
                insertion_idx = i
                break
            end
            -- Same page numbers.
            -- (We can trust page numbers, and only compare xpointers when both
            -- resolve to the same page.)
            if xpointer and item.xpointer then
                local order = self.document:compareXPointers(xpointer, item.xpointer)
                if order > 0 then -- item.xpointer after xpointer
                    insertion_idx = i
                    break
                elseif order == 0 then
                    matching_idx = i
                    break
                end
            else
                matching_idx = i
                break
            end
        end
    end
    -- We always return an index, and a boolean stating if this index is a match or not
    -- (if not, the index is the insertion index if we ever want to insert an item with
    -- the asked pageno/xpointer)
    return matching_idx or insertion_idx, matching_idx and true or false
end

function ReaderHandMade:hasPageTocItem(pageno, xpointer)
    local _, is_match = self:_getItemIndex(self.toc, pageno, xpointer)
    return is_match
end

function ReaderHandMade:addOrEditPageTocItem(pageno, when_updated_callback, selected_text, no_dialog)
    local xpointer, title
    if selected_text then
        -- If we get selected_text, it's from the highlight dialog after text selection
        title = selected_text.text
        if self.ui.rolling then
            xpointer = selected_text.pos0
            pageno = self.document:getPageFromXPointer(xpointer)
        else
            pageno = selected_text.pos0.page
        end
    end
    local idx, item_found = self:_getItemIndex(self.toc, pageno, xpointer)
    local item
    if item_found then
        -- Chapter found: it's an update (edit text or remove item)
        item = self.toc[idx]
    else
        -- No chapter starting on this page or at this xpointer:
        -- we'll add a new item
        if not xpointer and self.ui.rolling and type(pageno) == "number" then
            xpointer = self.document:getPageXPointer(pageno)
        end
        item = {
            title = title or "",
            page = pageno,
            xpointer = xpointer,
            depth = 1, -- we only support 1-level chapters to keep the UX simple
        }
    end
    if no_dialog then
        if item_found then return true end  -- no changes if existing TOC entry
        if selected_text then -- via highlight dialog
            item.title = selected_text.text
            table.insert(self.toc, idx, item)
            self.ui:handleEvent(Event:new("UpdateToc"))
        else -- via Page browser
            item.title = ""
            table.insert(self.toc, idx, item)
            self.ui:handleEvent(Event:new("UpdateToc"))
            if when_updated_callback then
                when_updated_callback()
            end
        end
        return true
    end
    local dialog
    dialog = InputDialog:new{
        title = item_found and _("Edit custom TOC chapter") or _("Create new custom ToC chapter"),
        input = item.title,
        input_hint = _("TOC chapter title"),
        description = T(_([[On page %1.]]), pageno),
        cursor_at_end = item_found and true or false, -- cursor at start for new entries for easy manual addition of chapter number
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = item_found and _("Save") or _("Create"),
                    is_enter_default = true,
                    callback = function()
                        item.title = dialog:getInputText()
                        UIManager:close(dialog)
                        if not item_found then
                            table.insert(self.toc, idx, item)
                        end
                        self.ui:handleEvent(Event:new("UpdateToc"))
                        if when_updated_callback then
                            when_updated_callback()
                        end
                    end,
                },
            },
            item_found and {
                {
                    text = _("Remove"),
                    callback = function()
                        UIManager:close(dialog)
                        table.remove(self.toc, idx)
                        self.ui:handleEvent(Event:new("UpdateToc"))
                        if when_updated_callback then
                            when_updated_callback()
                        end
                    end,
                },
                selected_text and
                    {
                        text = _("Use selected text"),
                        callback = function()
                            -- Just replace the text without saving, to allow editing/fixing it
                            dialog:setInputText(selected_text.text, nil, true)
                        end,
                    } or nil,
            } or nil,
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return true
end

function ReaderHandMade:isInHiddenFlow(pageno)
    local idx, is_match = self:_getItemIndex(self.flow_points, pageno)
    if is_match then
        return self.flow_points[idx].hidden
    else
        if idx > 1 then
            return self.flow_points[idx-1].hidden
        end
    end
    -- Before any first flow_point: not hidden
    return false
end

function ReaderHandMade:toggleHiddenFlow(pageno)
    self.ui.annotation:setNeedsUpdateFlag()
    local idx, is_match = self:_getItemIndex(self.flow_points, pageno)
    if is_match then
        -- Just remove the item (it feels we can, and that we don't
        -- have to just toggle its hidden value)
        table.remove(self.flow_points, idx)
        self:updateDocFlows()
        return
    end
    local hidden
    if idx > 1 then
        local previous_item = self.flow_points[idx-1]
        hidden = not previous_item.hidden
    else
        -- First item, can only start an hidden flow
        hidden = true
    end
    local xpointer
    if self.ui.rolling and type(pageno) == "number" then
        xpointer = self.document:getPageXPointer(pageno)
    end
    local item = {
        hidden = hidden,
        page = pageno,
        xpointer = xpointer,
    }
    table.insert(self.flow_points, idx, item)
    -- We could remove any followup item(s) with the same hidden state, but by keeping them,
    -- we allow users to adjust the start of a flow without killing its end. One can clean
    -- all the unnefective ones via the "Clear inactive marked pages" menu item.
    self:updateDocFlows()
end

function ReaderHandMade:updateDocFlows()
    local flows = {}
    local inactive_flow_points = {}
    -- (getPageCount(), needing the document to be fully loaded, is not available
    -- until ReaderReady, so be sure this is called only after ReaderReady.)
    local nb_pages = self.document:getPageCount()
    local nb_hidden_pages = 0
    local cur_hidden_flow
    for i, point in ipairs(self.flow_points) do
        if point.hidden and not cur_hidden_flow then
            cur_hidden_flow = {point.page, 0}
        elseif not point.hidden and cur_hidden_flow then
            local cur_hidden_pages = point.page - cur_hidden_flow[1]
            if cur_hidden_pages > 0 then
                cur_hidden_flow[2] = cur_hidden_pages
                nb_hidden_pages = nb_hidden_pages + cur_hidden_pages
                table.insert(flows, cur_hidden_flow)
            end
            cur_hidden_flow = nil
        else
            table.insert(inactive_flow_points, i)
        end
    end
    if cur_hidden_flow then
        local cur_hidden_pages = nb_pages + 1 - cur_hidden_flow[1]
        if cur_hidden_pages > 0 then
            cur_hidden_flow[2] = cur_hidden_pages
            nb_hidden_pages = nb_hidden_pages + cur_hidden_pages
            table.insert(flows, cur_hidden_flow)
        end
    end
    local first_linear_page = 1
    local last_linear_page = nb_pages
    if #flows > 0 then
        local flow = flows[1]
        if flow[1] == 1 then -- book first page is in a hidden flow
            first_linear_page = flow[1] + flow[2]
        end
        flow = flows[#flows]
        if flow[1] + flow[2] == nb_pages then -- book last page is in a hidden flow
            last_linear_page = flow[1] - 1
        end
    end
    -- CreDocument adds and item with key [0] with info about the main flow
    flows[0] = {first_linear_page, nb_pages - nb_hidden_pages}
    self.last_linear_page = last_linear_page
    self.flows = flows
    self.inactive_flow_points = inactive_flow_points
    -- We plug our flows table into the document, as some code peeks into it
    self.document.flows = self.flows
end

function ReaderHandMade:setupFlows(no_event)
    if self.flows_enabled then
        self:updateDocFlows()
        -- If enabled, plug some methods into the document object,
        -- so they are used instead of the methods from its class.
        self.document.hasHiddenFlows = function(this)
            return true
        end
        self.document.cacheFlows = function(this)
            return
        end
        self.document.getPageFlow = function(this, page)
            for i, flow in ipairs(self.flows) do
                if page < flow[1] then
                    return 0 -- page is not in a hidden flow
                end
                if page < flow[1] + flow[2] then
                    return i
                end
            end
            return 0
        end
        self.document.getFirstPageInFlow = function(this, flow)
            return self.flows[flow][1]
        end
        self.document.getTotalPagesInFlow = function(this, flow)
            return self.flows[flow][2]
        end
        self.document.getPageNumberInFlow = function(this, page)
            local nb_hidden_pages = 0
            for i, flow in ipairs(self.flows) do
                if page < flow[1] then
                    break -- page is not in a hidden flow
                end
                if page < flow[1] + flow[2] then
                    return page - flow[1] + 1
                end
                nb_hidden_pages = nb_hidden_pages + flow[2]
            end
            return page - nb_hidden_pages
        end
        self.document.getLastLinearPage = function(this)
            return self.last_linear_page
        end
        -- We can reuse as-is these ones from CreDocument, which uses the ones defined above.
        -- Note: these could probably be rewritten and simplified.
        local CreDocument = require("document/credocument")
        self.document.getTotalPagesLeft = CreDocument.getTotalPagesLeft
        self.document.getNextPage = CreDocument.getNextPage
        self.document.getPrevPage = CreDocument.getPrevPage
    else
        -- Remove all our overrides, so the class methods can be used again
        self.document.hasHiddenFlows = nil
        self.document.cacheFlows = nil
        self.document.getPageFlow = nil
        self.document.getFirstPageInFlow = nil
        self.document.getTotalPagesInFlow = nil
        self.document.getPageNumberInFlow = nil
        self.document.getLastLinearPage = nil
        self.document.getTotalPagesLeft = nil
        self.document.getNextPage = nil
        self.document.getPrevPage = nil
        self.document.flows = nil
        if self.document.cacheFlows then
            self.document:cacheFlows()
        end
    end
    if not no_event then
        self.ui:handleEvent(Event:new("UpdateToc"))
        -- Needed to skip hidden flows if PDF in scroll mode
        self.ui:handleEvent(Event:new("InitScrollPageStates"))
    end
end

return ReaderHandMade
