
ReaderKoptinterface = InputContainer:new{}

function ReaderKoptinterface:onReadSettings(config)
	self.normal_zoom_mode = config:readSetting("zoom_mode") or "page"
	if self.document.configurable.text_wrap == 1 then
		self.ui:handleEvent(Event:new("SetZoomMode", "page", "koptinterface"))
	else
		self.ui:handleEvent(Event:new("SetZoomMode", self.normal_zoom_mode, "koptinterface"))
	end
end

function ReaderKoptinterface:onRestoreZoomMode(zoom_mode)
	self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode or self.normal_zoom_mode, "koptinterface"))
	return true
end

function ReaderKoptinterface:onSetZoomMode(zoom_mode, orig)
	if orig ~= "koptinterface" then
		self.normal_zoom_mode = zoom_mode
	end
end
