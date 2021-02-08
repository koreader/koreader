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
            self.enabled = true
        else
            self.label_widget.dim = false
            self.enabled = true
        end
    end
end

function Button:disable()
    if self.enabled then
        if self.text then
            self.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
            self.enabled = false
        else
            self.label_widget.dim = true
            self.enabled = false
        end
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

function Button:onTapSelectButton()
    -- NOTE: We have a few tricks up our sleeve in case our parent is inside a translucent MovableContainer...
    local was_translucent = self.show_parent and self.show_parent.movable and self.show_parent.movable.alpha
    -- We make a distinction between transparency pre- and post- callback, because if a widget *was* transparent,
    -- but no longer is post-callback, we want to ensure that we refresh the *full* container,
    -- instead of just the button's frame, in order to avoid leaving bits of the widget transparent ;).
    local is_translucent = was_translucent

    if self.enabled and self.callback then
        if G_reader_settings:isFalse("flash_ui") then
            self.callback()
            -- Check if the callback reset transparency...
            is_translucent = was_translucent and self.show_parent.movable.alpha
        else
            -- Highlighting
            --
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

                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
            else
                self[1].invert = true
                UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
            end
            UIManager:setDirty(nil, function()
                return "fast", self[1].dimen
            end)

            -- Force the repaint *now*, so we have a chance to see the highlight on its own, before whatever the callback will do.
            if not self.vsync then
                -- NOTE: Except when a Button is flagged vsync, in which case we *want* to bundle the highlight with the callback, to prevent further delays
                UIManager:forceRePaint()
            end

            -- Unhighlight
            --
            -- We'll *paint* the unhighlight now, because at this point we can still be sure that our widget exists,
            -- and that anything we do will not impact whatever the callback does (i.e., that we draw *below* whatever the callback might show).
            -- We won't *fence* the refresh, though, to ensure that we do not delay the callback, and that the unhighlight essentially blends into whatever the callback does.
            -- Worst case scenario, we'll simply have "wasted" a tiny subwidget repaint if the callback closed us,
            -- but doing it this way allows us to avoid a large array of potential interactions with whatever the callback may paint/refresh if we were to handle the unhighlight post-callback,
            -- which would require a number of possibly brittle heuristics to handle.
            -- NOTE: If a Button is marked vsync, we want to keep it highlighted for now (in order for said highlight to be visible during the callback refresh), we'll remove the highlight post-callback.
            if not self.vsync then
                self[1].invert = false
                if self.text then
                    if self[1].radius == Size.radius.button then
                        self[1].radius = nil
                        self[1].background = self[1].background:invert()
                        self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
                    end
                    UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                else
                    UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
                end

                -- In case the callback itself won't enqueue a refresh region that includes us, do it ourselves.
                -- If the button is disabled, switch to UI to make sure the gray comes through unharmed ;).
                UIManager:setDirty(nil, function()
                    return self.enabled and "fast" or "ui", self[1].dimen
                end)
            end

            -- Callback
            --
            -- TODO: Double-check how this interacts with vsync/alpha (e.g., we may also be able to get rid of some of this).
            self.callback()
            -- Check if the callback reset transparency...
            is_translucent = was_translucent and self.show_parent.movable.alpha
            -- We don't want to fence the callback when we're *still* translucent, because we want a *single* refresh post-callback *and* post-unhighlight,
            -- in order to avoid flickering.
            if not is_translucent then
                UIManager:forceRePaint() -- Ensures whatever the callback wanted to paint will be shown *now*...
                if self.vsync then
                    -- NOTE: This is mainly useful when the callback caused a REAGL update that we do not explicitly fence already,
                    --       (i.e., Kobo Mk. 7).
                    UIManager:waitForVSync() -- ...and that the EPDC will not wait to coalesce it with the *next* update,
                                            -- because that would have a chance to noticeably delay it until the unhighlight.
                end
            end

            -- Unhighlight
            --
            -- NOTE: If a Button is marked vsync, we have a guarantee from the programmer that the widget it belongs to is still alive and top-level post-callback,
            --       so we can do this safely without risking UI glitches.
            -- FIXME: Dedupe.
            if self.vsync then
                self[1].invert = false
                if self.text then
                    if self[1].radius == Size.radius.button then
                        self[1].radius = nil
                        self[1].background = self[1].background:invert()
                        self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
                    end
                    UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                else
                    UIManager:widgetInvert(self[1], self[1].dimen.x, self[1].dimen.y)
                end

                -- In case the callback itself won't enqueue a refresh region that includes us, do it ourselves.
                -- If the button is disabled, switch to UI to make sure the gray comes through unharmed ;).
                UIManager:setDirty(nil, function()
                    return self.enabled and "fast" or "ui", self[1].dimen
                end)
            end
        end
    elseif self.tap_input then
        self:onInput(self.tap_input)
    elseif type(self.tap_input_func) == "function" then
        self:onInput(self.tap_input_func())
    end

    -- If our parent belongs to a translucent MovableContainer, repaint all the things to honor alpha without layering glitches,
    -- and refresh the full container, because the widget might have inhibited its own setDirty call to avoid flickering (c.f., *SpinWidget).
    if was_translucent then
        -- If the callback reset the transparency, we only need to repaint our parent
        UIManager:setDirty(is_translucent and "all" or self.show_parent, function()
            return "ui", self.show_parent.movable.dimen
        end)
        -- FIXME: vsync?
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
