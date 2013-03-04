
ReaderCoptListener = EventListener:new{}

function ReaderKoptListener:onReadSettings(config)
	local embedded_css = config:readSetting("copt_embedded_css")
	if embedded_css == 1 then
		table.insert(self.ui.postInitCallback, function()
	        self.ui:handleEvent(Event:new("ToggleEmbeddedStyleSheet"))
	    end)
	end
	local view_mode = config:readSetting("copt_view_mode")
	if view_mode == 0 then
		table.insert(self.ui.postInitCallback, function()
	        self.ui:handleEvent(Event:new("SetViewMode", "page"))
	    end)
	elseif view_mode == 1 then
		table.insert(self.ui.postInitCallback, function()
	        self.ui:handleEvent(Event:new("SetViewMode", "scroll"))
	    end)
	end
end
