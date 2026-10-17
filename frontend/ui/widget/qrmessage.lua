--[[--
Widget that displays a qr code.

Example:
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local sample
    sample = QRMessage:new{
        title = _("Send to Device"),
        text = _("my message"),
        invert_bidi = self.ui.view:shouldInvertBiDiLayoutMirroring(),
        timeout = 5,  -- This widget will vanish in 5 seconds.
    }
    UIManager:show(sample)
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local QRWidget = require("ui/widget/qrwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Input = Device.input
local Screen = Device.screen
local Size = require("ui/size")
local T = require("ffi/util").template
local _ = require("gettext")

local HARD_MAX_BYTES = QRWidget.MAX_BYTES -- 2953
local PREFIX_RESERVE = 15
local MAX_PAYLOAD = HARD_MAX_BYTES - PREFIX_RESERVE
local DENSITY_THRESHOLD = math.floor(MAX_PAYLOAD * 0.85) -- (85% of max capacity, roughly ~2500 bytes).

local QRMessage = InputContainer:extend{
    modal = true,
    stop_events_propagation = true,
    timeout = nil, -- in seconds
    _timeout_func = nil,
    title = nil,
    text = nil,  -- The text to encode.
    width = nil, -- screen width.
    height = nil, -- screen height.
    dismiss_callback = nil,
    alpha = nil,
    scale_factor = 1,
    pages = nil,
    page_num = 1,
    invert_bidi = false,
}

function QRMessage:init()
    if self.invert_bidi then
        BD.invert()
    end
    self.text = self.text or ""
    self.pages = self.splitText(self.text)
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()

    self:registerKeyEvents()
    if Device:isTouchDevice() then
        local full_screen = Geom:new{
            x = 0, y = 0,
            w = self.width,
            h = self.height,
        }
        self.ges_events.DiagonalSwipe = {
            GestureRange:new{ ges = "swipe", range = full_screen }
        }
        if #self.pages > 1 then
            self.ges_events.Swipe = {
                GestureRange:new{ ges = "swipe", range = full_screen }
            }
        end
    end

    self:_buildLayout()
end

function QRMessage:registerKeyEvents()
    if Device:hasKeys() then
        if #self.pages > 1 then
            self.key_events.NextPage = { { Input.group.PgFwd } }
            self.key_events.PrevPage = { { Input.group.PgBack } }
        end
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.FullRefresh = { { { "Press", "F5" } } }
    end
end
QRMessage.onPhysicalKeyboardConnected = QRMessage.registerKeyEvents

-- Divides large payloads evenly to maximise matrix memory caching,
-- avoids breaking UTF-8 characters, and prepends sequence markers.
-- The page count is sized so the average chunk stays within DENSITY_THRESHOLD,
-- keeping symbols below the maximum version rather than at its limit.
function QRMessage.splitText(text)
    if not text or text == "" then return {} end

    local len = #text
    -- If the text fits comfortably in one code, return it as-is
    if len <= DENSITY_THRESHOLD then
        return {text}
    end

    local pages = math.ceil(len / DENSITY_THRESHOLD)
    local chunks = {}
    local current_idx = 1
    while current_idx <= len do
        local remaining_pages = pages - #chunks
        local end_idx
        if remaining_pages <= 1 then
            -- Last planned chunk takes whatever is left.
            end_idx = len
        else
            -- Re-derive the target from what is left, so any UTF-8 step-back
            -- shortfall is spread over the remaining chunks instead of
            -- accumulating into a runt.
            local target = math.ceil((len - current_idx + 1) / remaining_pages)
            end_idx = math.min(current_idx + target - 1, len)
        end
        local hard_end = end_idx

        -- UTF-8 boundary check: if the byte immediately following our cut is a
        -- continuation byte (10xxxxxx, decimal 128-191), step back.
        while end_idx >= current_idx and end_idx < len do
            local b = string.byte(text, end_idx + 1)
            if b < 0x80 or b >= 0xC0 then
                break
            end
            end_idx = end_idx - 1
        end
        -- Invalid UTF-8 (no lead byte within the chunk): hard cut rather than
        -- emitting an empty chunk and no forward progress.
        if end_idx < current_idx then
            end_idx = hard_end
        end

        chunks[#chunks + 1] = text:sub(current_idx, end_idx)
        current_idx = end_idx + 1
    end

    local total = #chunks
    for i, chunk in ipairs(chunks) do
        chunks[i] = string.format("(%d/%d) ", i, total) .. chunk
    end
    return chunks
end

function QRMessage:_buildLayout()
    local num_pages = #self.pages
    local padding = Size.padding.fullscreen
    local pad_top = 0
    local pad_bottom = (num_pages > 1) and 0 or padding

    local title
    if self.title and self.title ~= "" then
        title = self.title .. T(_(" (%1 bytes)"), #self.text)
    else
        title = T(_("Scan me (%1 bytes)"), #self.text)
    end
    self.title_bar = TitleBar:new{
        width = self.width,
        fullscreen = true,
        align = "center",
        title = title,
        title_top_padding = Screen:scaleBySize(6),
        button_padding = Screen:scaleBySize(5),
        right_icon_size_ratio = 1,
        close_callback = function() self:onClose() end,
        show_parent = self.show_parent or self,
    }

    -- build the footer first (if needed) to measure its height
    local footer = nil
    if num_pages > 1 then
        local chevron_left = "chevron.left"
        local chevron_right = "chevron.right"
        local chevron_first = "chevron.first"
        local chevron_last = "chevron.last"

        if BD.mirroredUILayout() then
            chevron_left, chevron_right = chevron_right, chevron_left
            chevron_first, chevron_last = chevron_last, chevron_first
        end

        local btn_first = Button:new{
            icon = chevron_first,
            bordersize = 0,
            callback = function() self:onFirstPage() end,
            show_parent = self,
        }
        local btn_prev = Button:new{
            icon = chevron_left,
            bordersize = 0,
            callback = function() self:onPrevPage() end,
            show_parent = self,
        }
        local btn_next = Button:new{
            icon = chevron_right,
            bordersize = 0,
            callback = function() self:onNextPage() end,
            show_parent = self,
        }
        local btn_last = Button:new{
            icon = chevron_last,
            bordersize = 0,
            callback = function() self:onLastPage() end,
            show_parent = self,
        }
        self.footer_buttons = {
            first = btn_first, prev = btn_prev, next = btn_next, last = btn_last,
        }
        local spacer = HorizontalSpan:new{ width = Screen:scaleBySize(32) }
        self.page_indicator = TextWidget:new{
            text = T(_("Page %1 of %2"), self.page_num, num_pages),
            face = Font:getFace("smallinfofont"),
        }
        footer = HorizontalGroup:new{
            align = "center",
            btn_first, spacer, btn_prev, spacer, self.page_indicator, spacer, btn_next, spacer, btn_last,
        }
    end

    -- calculate target dimensions for the QR code
    local target_content_h = self.height and (self.height - pad_top - pad_bottom)
    local target_img_h = target_content_h
    if target_img_h then
        target_img_h = target_img_h - self.title_bar:getSize().h
        if footer then
            target_img_h = target_img_h - footer:getSize().h
        end
    end
    self.img_w = self.width - (padding * 2)
    self.img_h = target_img_h

    local elements = {
        align = "center",
        self.title_bar,
        self:_makeImage(),
    }
    if footer then
        table.insert(elements, footer)
    end
    self.footer = footer
    self.content_group = VerticalGroup:new(elements)

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        height = self.height,
        width = self.width,
        padding_top = pad_top,
        padding_bottom = pad_bottom,
        padding_left = 0,
        padding_right = 0,
        bordersize = 0,
        self.content_group,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }
    self:_syncFooter()
end

function QRMessage:_makeImage()
    local qr = QRWidget:new{
        text = self.pages[self.page_num],
        width = self.img_w,
        height = self.img_h,
        alpha = self.alpha,
        scale_factor = self.scale_factor,
    }
    if qr.image then return qr end
    -- QRWidget has logged the reason. An ImageWidget with no image throws in
    -- getSize(), so we show an error in its place.
    return CenterContainer:new{
        dimen = Geom:new{ w = self.img_w, h = self.img_h },
        TextWidget:new{
            text = _("Could not generate a QR code"),
            face = Font:getFace("infofont"),
            max_width = self.img_w,
        },
    }
end

function QRMessage:_syncFooter()
    if not self.footer then return end
    local num_pages = #self.pages
    local has_prev = self.page_num > 1
    local has_next = self.page_num < num_pages
    self.page_indicator:setText(T(_("Page %1 of %2"), self.page_num, num_pages))
    self.footer_buttons.first:enableDisable(has_prev)
    self.footer_buttons.prev:enableDisable(has_prev)
    self.footer_buttons.next:enableDisable(has_next)
    self.footer_buttons.last:enableDisable(has_next)
    self.footer:resetLayout()
end

-- Per-page update only: swap the QR and refresh the footer state.
function QRMessage:_renderPage()
    local old_image = self.content_group[2]
    self.content_group[2] = self:_makeImage()
    old_image:free()
    self.content_group:resetLayout()
    self:_syncFooter()
end

function QRMessage:_goToPage(page)
    if page >= 1 and page <= #self.pages and page ~= self.page_num then
        self.page_num = page
        self:_renderPage()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function QRMessage:onNextPage()
    return self:_goToPage(self.page_num + 1)
end

function QRMessage:onPrevPage()
    return self:_goToPage(self.page_num - 1)
end

function QRMessage:onFirstPage()
    return self:_goToPage(1)
end

function QRMessage:onLastPage()
    return self:_goToPage(#self.pages)
end

local DIAGONAL_DIRECTIONS = {
    northeast = true, northwest = true, southeast = true, southwest = true,
}
function QRMessage:onDiagonalSwipe(_, ges)
    -- Any diagonal swipe forces a full refresh.
    if DIAGONAL_DIRECTIONS[ges.direction] then
        self:onFullRefresh()
        return true
    end
    return false
end

function QRMessage:onSwipe(_, ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        return self:onNextPage()
    elseif direction == "east" then
        return self:onPrevPage()
    end
    return false
end

function QRMessage:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen -- i.e., frame
    end)
    -- If we were closed early, drop the scheduled timeout
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end

    if self.invert_bidi then
        BD.resetInvert()
    end
    local image = self.content_group and self.content_group[2]
    if image and image.free then
        image:free()
    end

    if self.dismiss_callback then
        self.dismiss_callback()
        self.dismiss_callback = nil
    end
end

function QRMessage:onShow()
    -- triggered by the UIManager after we got successfully shown (not yet painted)
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
    return true
end

function QRMessage:onFullRefresh()
    UIManager:setDirty(self, "full")
    return true
end

function QRMessage:onClose()
    UIManager:close(self)
    return true
end

return QRMessage
