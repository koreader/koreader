local EventListener = require("ui/widget/eventlistener")

local ReaderCoptListener = EventListener:new{}

function ReaderCoptListener:onReadSettings(config)
    local view_mode = config:readSetting("copt_view_mode")
    if view_mode == 0 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("page")
        end)
    elseif view_mode == 1 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("scroll")
        end)
    end

    local status_line = config:readSetting("copt_status_line") or DCREREADER_PROGRESS_BAR
    self.document:setStatusLineProp(status_line)
end

function ReaderCoptListener:onSetFontSize(font_size)
    self.document.configurable.font_size = font_size
end

return ReaderCoptListener
