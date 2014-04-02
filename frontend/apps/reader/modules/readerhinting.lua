local EventListener = require("ui/widget/eventlistener")

local ReaderHinting = EventListener:new{
    hinting_states = {}
}

function ReaderHinting:onHintPage()
    if not self.view.hinting then return true end
    for i=1, DHINTCOUNT do
        if self.view.state.page + i <= self.ui.document.info.number_of_pages then
            self.ui.document:hintPage(
                self.view.state.page + i,
                self.zoom:getZoom(self.view.state.page + i),
                self.view.state.rotation,
                self.view.state.gamma,
                self.view.render_mode)
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
