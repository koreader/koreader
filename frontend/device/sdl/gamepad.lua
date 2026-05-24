local Gamepad = {
    axis_press_deadzone = 5000,
    axis_release_deadzone = 4500,
    axis_repeat_delay_s = 0.5,
    axis_repeat_interval_s = 0.2,
    held_axis_directions = {},
    repeating_axis = nil,
    repeating_direction = nil,
    button_ids = {
        [0] = "a", [1] = "b", [2] = "x", [3] = "y", [4] = "back", [5] = "guide",
        [6] = "start", [7] = "left_stick", [8] = "right_stick", [9] = "left_shoulder",
        [10] = "right_shoulder", [11] = "dpad_up", [12] = "dpad_down",
        [13] = "dpad_left", [14] = "dpad_right", [15] = "misc_1",
    },
    axis_ids = {
        [0] = "left_x", [1] = "left_y", [2] = "right_x", [3] = "right_y",
        [4] = "left_trigger", [5] = "right_trigger",
    },
    button_names = {
        [0] = "South (A/B)",
        [1] = "East (B/A)",
        [2] = "West (X/Y)",
        [3] = "North (Y/X)",
        [4] = "Back",
        [5] = "Guide",
        [6] = "Start",
        [7] = "Left Stick (L3)",
        [8] = "Right Stick (R3)",
        [9] = "Left Shoulder (L1)",
        [10] = "Right Shoulder (R1)",
        [11] = "D-pad Up",
        [12] = "D-pad Down",
        [13] = "D-pad Left",
        [14] = "D-pad Right",
        [15] = "Misc 1",
    },
    axis_names = {
        [0] = "Left Stick X",
        [1] = "Left Stick Y",
        [2] = "Right Stick X",
        [3] = "Right Stick Y",
        [4] = "Left Trigger",
        [5] = "Right Trigger",
    },
    button_key_names = {
        [0] = "Press",
        [1] = "Back",
        [3] = "ContextMenu",
        [4] = "RPgBack",
        [5] = "RPgFwd",
        [6] = "Menu",
        [7] = "Menu",
        [9] = "RPgBack",
        [10] = "RPgFwd",
        [11] = "Up",
        [12] = "Down",
        [13] = "Left",
        [14] = "Right",
    },
    axis_key_names = {
        [0] = { minus = "Left", plus = "Right" },
        [1] = { minus = "Up", plus = "Down" },
        [3] = { minus = "RPgBack", plus = "RPgFwd" },
    },
}

function Gamepad:getAxisDirection(value, held_direction)
    local deadzone = held_direction and self.axis_release_deadzone or self.axis_press_deadzone
    if value > -deadzone and value < deadzone then
        return nil
    end
    return value < 0 and "minus" or "plus"
end

function Gamepad:shouldProcessAxisMotion(axis, value)
    local held_direction = self.held_axis_directions[axis]
    local direction = self:getAxisDirection(value, held_direction)
    if direction == held_direction then
        return false
    end

    self.held_axis_directions[axis] = direction
    if direction == nil and self.repeating_axis == axis then
        self.repeating_axis = nil
        self.repeating_direction = nil
    end
    return direction ~= nil
end

function Gamepad:getHeldDirection(axis)
    return self.held_axis_directions[axis]
end

function Gamepad:setRepeatingAxis(axis)
    self.repeating_axis = axis
    self.repeating_direction = self.held_axis_directions[axis]
end

function Gamepad:isRepeatingAxisHeld()
    return self.repeating_axis ~= nil
        and self.held_axis_directions[self.repeating_axis] == self.repeating_direction
end

function Gamepad:clearRepeatingAxis(axis)
    if axis == nil or self.repeating_axis == axis then
        self.repeating_axis = nil
        self.repeating_direction = nil
    end
end

function Gamepad:getHeldAxisEvent()
    if not self:isRepeatingAxisHeld() then
        return nil
    end

    local value = self.repeating_direction == "minus"
        and -(self.axis_press_deadzone + 1)
        or self.axis_press_deadzone + 1
    return {
        axis = self.repeating_axis,
        value = value,
    }
end

function Gamepad:getAxisHotkeyName(axis, value)
    local id = self.axis_ids[axis]
    local direction = self:getAxisDirection(value)
    if not id or not direction then
        return nil
    end
    return "joy_axis_" .. id .. "_" .. direction
end

function Gamepad:getAxisKeyName(axis, value)
    local mapping = self.axis_key_names[axis]
    local direction = self:getAxisDirection(value)
    if not mapping or not direction then
        return nil
    end
    return mapping[direction]
end

function Gamepad:getButtonKeyName(button)
    return self.button_key_names[button]
end

return Gamepad
