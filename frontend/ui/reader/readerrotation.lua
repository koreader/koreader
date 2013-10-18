local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local _ = require("gettext")

local ReaderRotation = InputContainer:new{
	ROTATE_ANGLE_THRESHOLD = 15,
	current_rotation = 0
}

function ReaderRotation:init()
	if Device:hasKeyboard() then
		self.key_events = {
			-- these will all generate the same event, just with different arguments
			RotateLeft = {
				{"J"},
				doc = _("rotate left by 90 degrees"),
				event = "Rotate", args = -90 },
			RotateRight = {
				{"K"},
				doc = _("rotate right by 90 degrees"),
				event = "Rotate", args = 90 },
		}
	end
	if Device:isTouchDevice() then
		self.ges_events = {
			RotateGes = {
				GestureRange:new{
					ges = "rotate",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			},
			TwoFingerPanRelease = {
				GestureRange:new{
					ges = "two_finger_pan_release",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			}
		}
	end
end

-- TODO: reset rotation on new document, maybe on new page?

function ReaderRotation:onRotate(rotate_by)
	self.current_rotation = (self.current_rotation + rotate_by) % 360
	self.ui:handleEvent(Event:new("RotationUpdate", self.current_rotation))
	return true
end

function ReaderRotation:onRotateGes(arg, ges)
	self.rotate_angle = ges.angle
	return true
end

function ReaderRotation:onTwoFingerPanRelease(arg, ges)
	if self.rotate_angle and self.rotate_angle > self.ROTATE_ANGLE_THRESHOLD then
		if Screen:getScreenMode() == "portrait" then
			self.ui:handleEvent(Event:new("SetScreenMode", "landscape"))
		else
			self.ui:handleEvent(Event:new("SetScreenMode", "portrait"))
		end
		self.rotate_angle = nil
	end
end

return ReaderRotation
