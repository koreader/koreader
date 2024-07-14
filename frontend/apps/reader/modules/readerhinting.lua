local EventListener = require("ui/widget/eventlistener")

local DHINTCOUNT = G_defaults:readSetting("DHINTCOUNT")

local ReaderHinting = EventListener:extend{
    hinting_states = nil, -- array
}

function ReaderHinting:init()
    self.hinting_states = {}
end

function ReaderHinting:onHintPage()
    if not self.view.hinting then return true end
    for i=1, DHINTCOUNT do
        if self.view.state.page + i <= self.document.info.number_of_pages then
            self.document:hintPage(
                self.view.state.page + i,
                self.zoom:getZoom(self.view.state.page + i),
                self.view.state.rotation,
                self.view.state.gamma)
        end
    end
    return true
end

function ReaderHinting:onSetHinting(hinting)
    self.view.hinting = hinting
end

function ReaderHinting:onDisableHinting()
    table.insert(self.hinting_states, self.view.hinting)
    self.view.hinting = false
    return true
end

function ReaderHinting:onRestoreHinting()
    self.view.hinting = table.remove(self.hinting_states)
    return true
end

return ReaderHinting
