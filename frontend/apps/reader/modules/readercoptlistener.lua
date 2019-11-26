local Event = require("ui/event")
local EventListener = require("ui/widget/eventlistener")

local ReaderCoptListener = EventListener:new{}

function ReaderCoptListener:onReadSettings(config)
    local view_mode = config:readSetting("copt_view_mode") or
           G_reader_settings:readSetting("copt_view_mode")
    if view_mode == 0 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("page")
        end)
    elseif view_mode == 1 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("scroll")
        end)
    end

    local status_line = config:readSetting("copt_status_line") or G_reader_settings:readSetting("copt_status_line") or 1
    self.ui:handleEvent(Event:new("SetStatusLine", status_line, true))
end

function ReaderCoptListener:onSetFontSize(font_size)
    self.document.configurable.font_size = font_size
end

return ReaderCoptListener
