
ReaderFlipping = LeftContainer:new{}

function ReaderFlipping:init()
	local widget = ImageWidget:new{
		file = "resources/icons/appbar.book.open.png",
	}
	local icon_size = widget:getSize()
	self.dimen = Geom:new{w = Screen:getWidth(), h = icon_size.h}
	self[1] = widget
end

function ReaderFlipping:onSetDogearVisibility(visible)
	self.view.dogear_visible = visible
	return true
end