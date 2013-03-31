
ReaderFlipping = LeftContainer:new{
	orig_reflow_mode = 0,
}

function ReaderFlipping:init()
	local widget = ImageWidget:new{
		file = "resources/icons/appbar.book.open.png",
	}
	local icon_size = widget:getSize()
	self.dimen = Geom:new{w = Screen:getWidth(), h = icon_size.h}
	self[1] = widget
end

function ReaderFlipping:onSetFlippingMode(flipping_mode)
	if flipping_mode then
		self.orig_reflow_mode = self.view.document.configurable.text_wrap
		self.view.document.configurable.text_wrap = 0
	else
		self.view.document.configurable.text_wrap = self.orig_reflow_mode
	end
	return true
end