
ReaderKoptListener = EventListener:new{}

function ReaderKoptListener:setZoomMode(zoom_mode)
	if self.document.configurable.text_wrap == 1 then
		-- in reflow mode only "page" zoom mode is valid so override any other zoom mode
		self.ui:handleEvent(Event:new("SetZoomMode", "page", "koptlistener"))
	else
		self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode, "koptlistener"))
	end
end

function ReaderKoptListener:onReadSettings(config)
	-- normal zoom mode is zoom mode used in non-reflow mode.
	self.normal_zoom_mode = config:readSetting("normal_zoom_mode") or "page"
	self:setZoomMode(self.normal_zoom_mode)
end

function ReaderKoptListener:onCloseDocument()
	self.ui.doc_settings:saveSetting("normal_zoom_mode", self.normal_zoom_mode)
end

function ReaderKoptListener:onRestoreZoomMode()
	-- "RestoreZoomMode" event is sent when reflow mode on/off is toggled
	self:setZoomMode(self.normal_zoom_mode)
	return true
end

function ReaderKoptListener:onSetZoomMode(zoom_mode, orig)
	if orig == "koptlistener" then return end
	-- capture zoom mode set outside of koptlistener which should always be normal zoom mode
	self.normal_zoom_mode = zoom_mode
	self:setZoomMode(self.normal_zoom_mode)
end
