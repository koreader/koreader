local EventListener = require("ui/widget/eventlistener")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local DHINTCOUNT = G_defaults:readSetting("DHINTCOUNT")

local ReaderHinting = EventListener:extend{
    hinting_states = nil, -- array
}

function ReaderHinting:init()
    self.hinting_states = {}
end

function ReaderHinting:onHintPage(_, opportunistic)
    if not self.view.hinting then return true end
    if self._hint_retry_fn then
        UIManager:unschedule(self._hint_retry_fn)
        self._hint_retry_fn = nil
    end
    local dir = (self.ui.paging and self.ui.paging.last_view_rel_diff) or 1
    if self.document:shouldDeferHint(self.view.state.page, dir, self.view.state) then
        self:_scheduleHintRetry(opportunistic)
        return true
    end

    local predicted = self.ui.paging
        and self.ui.paging.getNextViewHint
        and self.ui.paging:getNextViewHint()
    if predicted and predicted.page >= 1
            and predicted.page <= self.document.info.number_of_pages then
        local zoom, use_bbox
        if predicted.page == self.view.state.page and self.view.state.zoom then
            zoom = self.view.state.zoom
            use_bbox = self.view.use_bbox
        else
            zoom, use_bbox = self.zoom:getZoomForPage(predicted.page)
        end
        -- Evaluate all slots before dispatching slot 1 so bbox probes run
        -- while the worker is still idle.
        local slots = {
            { pageno = predicted.page, rect = predicted.rect,
              zoom = zoom, use_bbox = use_bbox },
        }
        for i = 2, DHINTCOUNT do
            local pageno = predicted.page + (dir > 0 and (i - 1) or -(i - 1))
            if pageno >= 1 and pageno <= self.document.info.number_of_pages then
                local z, ub = self.zoom:getZoomForPage(pageno)
                slots[#slots + 1] = {
                    pageno = pageno,
                    rect = self:getEntryEdgeRect(pageno, dir, z, ub),
                    zoom = z, use_bbox = ub,
                }
            end
        end
        self:_dispatchHintSlots(slots, opportunistic)
        return true
    end

    -- Fallback when prediction is unavailable (scroll mode, free zoom).
    local slots = {}
    for i = 1, DHINTCOUNT do
        local pageno = self.view.state.page + (dir > 0 and i or -i)
        if pageno >= 1 and pageno <= self.document.info.number_of_pages then
            local zoom, use_bbox = self.zoom:getZoomForPage(pageno)
            slots[#slots + 1] = {
                pageno = pageno,
                rect = self:getEntryEdgeRect(pageno, dir, zoom, use_bbox),
                zoom = zoom, use_bbox = use_bbox,
            }
        end
    end
    self:_dispatchHintSlots(slots, opportunistic)
    return true
end

--- Dispatch evaluated hint slots; slots >= 2 use `dispatch_only` so they park
-- instead of aborting slot 1 via a synchronous fallback.
function ReaderHinting:_dispatchHintSlots(slots, opportunistic)
    for i, slot in ipairs(slots) do
        self.document:hintPage(
            slot.pageno,
            slot.zoom,
            self.view.state.rotation,
            self.view.state.gamma,
            self.view.state.saturation,
            slot.rect,
            (i > 1 or opportunistic) and true or nil,
            slot.use_bbox)
    end
end

--- Poll until the worker settles, then re-run `onHintPage`.
function ReaderHinting:_scheduleHintRetry(opportunistic, attempt)
    attempt = (attempt or 0) + 1
    if attempt > 250 then
        return
    end
    if self._hint_retry_fn then
        UIManager:unschedule(self._hint_retry_fn)
    end
    self._hint_retry_fn = function()
        self._hint_retry_fn = nil
        if not self.ui or not self.view or not self.view.hinting then
            return
        end
        if self.document:hasPendingBackgroundRender() then
            self:_scheduleHintRetry(opportunistic, attempt)
            return
        end
        self:onHintPage(nil, opportunistic)
    end
    UIManager:scheduleIn(0.02, self._hint_retry_fn)
end

function ReaderHinting:onCloseDocument()
    if self._hint_retry_fn then
        UIManager:unschedule(self._hint_retry_fn)
        self._hint_retry_fn = nil
    end
end

--- Compute the viewport-sized entry-edge rect for `pageno` in direction `dir`.
-- @tparam int pageno
-- @tparam int dir >0 for top edge, <0 for bottom edge
-- @tparam[opt] number zoom
-- @tparam[opt] bool use_bbox
-- @treturn Geom
function ReaderHinting:getEntryEdgeRect(pageno, dir, zoom, use_bbox)
    if not zoom then
        zoom, use_bbox = self.zoom:getZoomForPage(pageno)
    end
    local page_area = self.view:getPageArea(pageno, zoom, self.view.state.rotation, use_bbox, true)
    local w = math.min(self.view.dimen.w, page_area.w)
    local h = self.view.dimen.h
    if self.view.footer_visible and self.view.footer
            and not self.view.footer.settings.reclaim_height then
        h = h - self.view.footer:getHeight()
    end
    h = math.min(h, page_area.h)
    local y = page_area.y
    if dir < 0 then
        y = page_area.y + page_area.h - h
    end
    return Geom:new{ x = page_area.x, y = y, w = w, h = h }
end

function ReaderHinting:onSetHinting(hinting)
    self.view.hinting = hinting
end

function ReaderHinting:onDisableHinting()
    table.insert(self.hinting_states, self.view.hinting)
    self.view.hinting = false
    return true
end

function ReaderHinting:onRestoreHinting()
    self.view.hinting = table.remove(self.hinting_states)
    return true
end

return ReaderHinting
