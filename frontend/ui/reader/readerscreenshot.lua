
ReaderScreenshot = InputContainer:new{}

function ReaderScreenshot:init()
	local diagonal = math.sqrt(
		math.pow(Screen:getWidth(), 2) +
		math.pow(Screen:getHeight(), 2)
	)
	self.ges_events = {
		Screenshot = {
			GestureRange:new{
				ges = "two_finger_tap",
				scale = {diagonal - scaleByDPI(80), diagonal},
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

