--[[--
A button widget that shows text or an icon and handles callback when tapped.

@usage
    local Button = require("ui/widget/button")
    local button = Button:new{
        text = _("Press me!"),
        enabled = false, -- defaults to true
        callback = some_callback_function,
        width = Screen:scaleBySize(50),
        max_width = Screen:scaleBySize(100),
        bordersize = Screen:scaleBySize(3),
        margin = 0,
        padding = Screen:scaleBySize(2),
    }
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")

local Button = InputContainer:new{
    text = nil, -- mandatory
    text_func = nil,
    icon = nil,
    icon_width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    icon_height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    icon_rotation_angle = 0,
    preselect = false,
    callback = nil,
    enabled = true,
    hidden = false,
    allow_hold_when_disabled = false,
    margin = 0,
    bordersize = Size.border.button,
    background = Blitbuffer.COLOR_WHITE,
    radius = nil,
    padding = Size.padding.button,
    padding_h = nil,
    padding_v = nil,
    width = nil,
    max_width = nil,
    text_font_face = "cfont",
    text_font_size = 20,
    text_font_bold = true,
    vsync = nil, -- when "flash_ui" is enabled, allow bundling the highlight with the callback, and fence that batch away from the unhighlight. Avoid delays when callback requires a "partial" on Kobo Mk. 7, c.f., ffi/framebuffer_mxcfb for more details.
}

function Button:init()
    -- Prefer an optional text_func over text
    if self.text_func and type(self.text_func) == "function" then
        self.text = self.text_func()
    end

    -- Point tap_input to hold_input if requested
    if self.call_hold_input_on_tap then
        self.tap_input = self.hold_input
    end

    if not self.padding_h then
        self.padding_h = self.padding
    end
    if not self.padding_v then
        self.padding_v = self.padding
    end

    if self.text then
        self.label_widget = TextWidget:new{
            text = self.text,
            max_width = self.max_width and self.max_width - 2*self.padding_h - 2*self.margin - 2*self.bordersize or nil,
            fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            bold = self.text_font_bold,
            face = Font:getFace(self.text_font_face, self.text_font_size)
        }
    else
        self.label_widget = IconWidget:new{
            icon = self.icon,
            rotation_angle = self.icon_rotation_angle,
            dim = not self.enabled,
            width = self.icon_width,
            height = self.icon_height,
        }
    end
    local widget_size = self.label_widget:getSize()
    if self.width == nil then
        self.width = widget_size.w
    end
    -- set FrameContainer content
    self.frame = FrameContainer:new{
        margin = self.margin,
        bordersize = self.bordersize,
        background = self.background,
        radius = self.radius,
        padding_top = self.padding_v,
        padding_bottom = self.padding_v,
        padding_left = self.padding_h,
        padding_right = self.padding_h,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget_size.h
            },
            self.label_widget,
        }
    }
    if self.preselect then
        self.frame.invert = true
    end
    self.dimen = self.frame:getSize()
    self[1] = self.frame
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelectButton = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Tap Button",
            },
            HoldSelectButton = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Button",
            },
            -- Safe-guard for when used inside a MovableContainer
            HoldReleaseSelectButton = {
                GestureRange:new{
                    ges = "hold_release",
                    range = self.dimen,
                },
            }
        }
    end
end

function Button:setText(text, width)
    if text ~= self.text then
        -- Don't trash the frame if we're already a text button, and we're keeping the geometry intact
        if self.text and width and width == self.width then
            self.text = text
            self.label_widget:setText(text)
        else
            self.text = text
            self.width = width
            self:init()
        end
    end
end

function Button:setIcon(icon)
    if icon ~= self.icon then
        self.icon = icon
        self.width = nil
        self:init()
    end
end

function Button:onFocus()
    if self.no_focus then return end
    self.frame.invert = true
    return true
end

function Button:onUnfocus()
    if self.no_focus then return end
    self.frame.invert = false
    return true
end

function Button:enable()
    if not self.enabled then
        if self.text then
            self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
        else
            self.label_widget.dim = false
        end
        self.enabled = true
    end
end

function Button:disable()
    if self.enabled then
        if self.text then
            self.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
        else
            self.label_widget.dim = true
        end
        self.enabled = false
    end
end

-- This is used by pagination buttons with a hold_input registered that we want to *sometimes* inhibit,
-- meaning we want the Button disabled, but *without* dimming the text...
function Button:disableWithoutDimming()
    self.enabled = false
    if self.text then
        self.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
    else
        self.label_widget.dim = false
    end
end

function Button:enableDisable(enable)
    if enable then
        self:enable()
    else
        self:disable()
    end
end

function Button:hide()
    if self.icon and not self.hidden then
        self.frame.orig_background = self.frame.background
        self.frame.background = nil
        self.label_widget.hide = true
        self.hidden = true
    end
end

function Button:show()
    if self.icon and self.hidden then
        self.label_widget.hide = false
        self.frame.background = self.frame.orig_background
        self.hidden = false
    end
end

function Button:showHide(show)
    if show then
        self:show()
    else
        self:hide()
    end
end

-- Used by onTapSelectButton to handle visual feedback when flash_ui is enabled
function Button:_doFeedbackHighlight()
    -- NOTE: self[1] -> self.frame, if you're confused about what this does vs. onFocus/onUnfocus ;).
    if self.text then
        -- We only want the button's *highlight* to have rounded corners (otherwise they're redundant, same color as the bg).
        -- The nil check is to discriminate the default from callers that explicitly request a specific radius.
        if self[1].radius == nil then
            self[1].radius = Size.radius.button
            -- And here, it's easier to just invert the bg/fg colors ourselves,
            -- so as to preserve the rounded corners in one step.
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
            -- We do *NOT* set the invert flag, because it just adds an invertRect step at the end of the paintTo process,
            -- and we've already taken care of inversion in a way that won't mangle the rounded corners.
        else
            self[1].invert = true
        end

        -- This repaints *now*, unlike setDirty
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
    else
        self[1].invert = true
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
    end
    UIManager:setDirty(nil, "fast", self[1].dimen)
end

function Button:_undoFeedbackHighlight(is_translucent)
    if self.text then
        if self[1].radius == Size.radius.button then
            self[1].radius = nil
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
        else
            self[1].invert = false
        end
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
    else
        self[1].invert = false
        UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
    end

    if is_translucent then
        -- If our parent belongs to a translucent MovableContainer, we need to repaint it on unhighlight in order to honor alpha,
        -- because our highlight/unhighlight will have made the Button fully opaque.
        -- UIManager will detect transparency and then takes care of also repainting what's underneath us to avoid alpha layering glitches.
        UIManager:setDirty(self.show_parent, "ui", self[1].dimen)
    else
        -- In case the callback itself won't enqueue a refresh region that includes us, do it ourselves.
        -- If the button is disabled, switch to UI to make sure the gray comes through unharmed ;).
        UIManager:setDirty(nil, self.enabled and "fast" or "ui", self[1].dimen)
    end
end

function Button:onTapSelectButton()
    if self.enabled or self.allow_tap_when_disabled then
        if self.callback then
            if G_reader_settings:isFalse("flash_ui") then
                self.callback()
            else
                -- NOTE: We have a few tricks up our sleeve in case our parent is inside a translucent MovableContainer...
                local is_translucent = self.show_parent and self.show_parent.movable and self.show_parent.movable.alpha

                -- Highlight
                --
                self:_doFeedbackHighlight()

                -- Force the refresh by draining the refresh queue *now*, so we have a chance to see the highlight on its own, before whatever the callback will do.
                if not self.vsync then
                    -- NOTE: Except when a Button is flagged vsync, in which case we *want* to bundle the highlight with the callback, to prevent further delays
                    UIManager:forceRePaint()

                    -- NOTE: Yield to the kernel for a tiny slice of time, otherwise, writing to the same fb region as the refresh we've just requested may be race-y,
                    --       causing mild variants of our friend the papercut refresh glitch ;).
                    --       Remember that the whole eInk refresh dance is completely asynchronous: we *request* a refresh from the kernel,
                    --       but it's up to the EPDC to schedule that however it sees fit...
                    --       The other approach would be to *ask* the EPDC to block until it's *completely* done,
                    --       but that's too much (because we only care about it being done *reading* the fb),
                    --       and that could take upwards of 300ms, which is also way too much ;).
                    UIManager:yieldToEPDC()
                end

                -- Unhighlight
                --
                -- We'll *paint* the unhighlight now, because at this point we can still be sure that our widget exists,
                -- and that anything we do will not impact whatever the callback does (i.e., that we draw *below* whatever the callback might show).
                -- We won't *fence* the refresh (i.e., it's queued, but we don't actually drain the queue yet), though, to ensure that we do not delay the callback, and that the unhighlight essentially blends into whatever the callback does.
                -- Worst case scenario, we'll simply have "wasted" a tiny subwidget repaint if the callback closed us,
                -- but doing it this way allows us to avoid a large array of potential interactions with whatever the callback may paint/refresh if we were to handle the unhighlight post-callback,
                -- which would require a number of possibly brittle heuristics to handle.
                -- NOTE: If a Button is marked vsync, we want to keep it highlighted for now (in order for said highlight to be visible during the callback refresh), we'll remove the highlight post-callback.
                if not self.vsync then
                    self:_undoFeedbackHighlight(is_translucent)
                end

                -- Callback
                --
                self.callback()

                -- Check if the callback reset transparency...
                is_translucent = is_translucent and self.show_parent.movable.alpha

                UIManager:forceRePaint() -- Ensures whatever the callback wanted to paint will be shown *now*...
                if self.vsync then
                    -- NOTE: This is mainly useful when the callback caused a REAGL update that we do not explicitly fence via MXCFB_WAIT_FOR_UPDATE_COMPLETE already, (i.e., Kobo Mk. 7).
                    UIManager:waitForVSync() -- ...and that the EPDC will not wait to coalesce it with the *next* update,
                                                -- because that would have a chance to noticeably delay it until the unhighlight.
                end

                -- Unhighlight
                --
                -- NOTE: If a Button is marked vsync, we have a guarantee from the programmer that the widget it belongs to is still alive and top-level post-callback,
                --       so we can do this safely without risking UI glitches.
                if self.vsync then
                    self:_undoFeedbackHighlight(is_translucent)
                    UIManager:forceRePaint()
                end
            end
        elseif self.tap_input then
            self:onInput(self.tap_input)
        elseif type(self.tap_input_func) == "function" then
            self:onInput(self.tap_input_func())
        end
    end

    if self.readonly ~= true then
        return true
    end
end

-- Allow repainting and refreshing *a* specific Button, instead of the full screen/parent stack
function Button:refresh()
    -- We can only be called on a Button that's already been painted once, which allows us to know where we're positioned,
    -- thanks to the frame's geometry.
    -- e.g., right after a setText or setIcon is a no-go, as those kill the frame.
    --       (Although, setText, if called with the current width, will conserve the frame).
    if not self[1].dimen then
        logger.dbg("Button:", self, "attempted a repaint in an unpainted frame!")
        return
    end
    UIManager:widgetRepaint(self[1], self[1].dimen.x, self.dimen.y)

    UIManager:setDirty(nil, function()
        return self.enabled and "fast" or "ui", self[1].dimen
    end)
end

function Button:onHoldSelectButton()
    -- If we're going to process this hold, we must make
    -- sure to also handle its hold_release below, so it's
    -- not propagated up to a MovableContainer
    self._hold_handled = nil
    if self.enabled or self.allow_hold_when_disabled then
        if self.hold_callback then
            self.hold_callback()
            self._hold_handled = true
        elseif self.hold_input then
            self:onInput(self.hold_input, true)
            self._hold_handled = true
        elseif type(self.hold_input_func) == "function" then
            self:onInput(self.hold_input_func(), true)
            self._hold_handled = true
        end
    end
    if self.readonly ~= true then
        return true
    end
end

function Button:onHoldReleaseSelectButton()
    if self._hold_handled then
        self._hold_handled = nil
        return true
    end
    return false
end

return Button
