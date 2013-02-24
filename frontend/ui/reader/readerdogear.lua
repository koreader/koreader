
ReaderDogear = RightContainer:new{}

function ReaderDogear:init()
	local widget = ImageWidget:new{
		file = "resources/icons/dogear.png",
	}
	local icon_size = widget:getSize()
	self.dimen = Geom:new{w = Screen:getWidth(), h = icon_size.h}
	self[1] = widget
end

function ReaderDogear:onSetDogearVisibility(visible)
	self.view.dogear_visible = visible
	return true
end