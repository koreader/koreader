
ReaderKoptListener = EventListener:new{}

function ReaderKoptListener:onReadSettings(config)
	self.normal_zoom_mode = config:readSetting("normal_zoom_mode") or "page"
	if self.document.configurable.text_wrap == 1 then
		self.ui:handleEvent(Event:new("SetZoomMode", "page", "koptlistener"))
	else
		self.ui:handleEvent(Event:new("SetZoomMode", self.normal_zoom_mode, "koptlistener"))
	end
end

function ReaderKoptListener:onCloseDocument()
	self.ui.doc_settings:saveSetting("normal_zoom_mode", self.normal_zoom_mode)
end

function ReaderKoptListener:onRestoreZoomMode(zoom_mode)
	self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode or self.normal_zoom_mode, "koptlistener"))
	return true
end

function ReaderKoptListener:onSetZoomMode(zoom_mode, orig)
	if orig ~= "koptlistener" then
		self.normal_zoom_mode = zoom_mode
	end
end
