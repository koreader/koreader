local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("ui/screen")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")

local ReaderScreenshot = InputContainer:new{}

function ReaderScreenshot:init()
	local diagonal = math.sqrt(
		math.pow(Screen:getWidth(), 2) +
		math.pow(Screen:getHeight(), 2)
	)
	self.ges_events = {
		Screenshot = {
			GestureRange:new{
				ges = "two_finger_tap",
				scale = {diagonal - Screen:scaleByDPI(100), diagonal},
				rate = 1.0,
			}
		},
	}
end

function ReaderScreenshot:onScreenshot()
	os.execute("screenshot")
	UIManager.full_refresh = true
	return true
end

return ReaderScreenshot
