
ReaderCoptListener = EventListener:new{}

function ReaderCoptListener:onReadSettings(config)
	local embedded_css = config:readSetting("copt_embedded_css")
	if embedded_css == 0 then
		table.insert(self.ui.postInitCallback, function()
	        self.ui:handleEvent(Event:new("ToggleEmbeddedStyleSheet", false))
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
	
	local copt_font_size = config:readSetting("copt_font_size") or 22
	if copt_font_size then
		table.insert(self.ui.postInitCallback, function()
		    self.ui.document:setFontSize(copt_font_size)
			self.ui:handleEvent(Event:new("UpdatePos"))
		end)
	end
	
	local copt_margins = config:readSetting("copt_page_margins")
	if copt_margins then
		table.insert(self.ui.postInitCallback, function()
			-- FIXME: SetPageMargins will mess up current reading position
			-- for now we simply disable this feature.
		    --self.ui:handleEvent(Event:new("SetPageMargins", copt_margins))
		end)
	end
end
