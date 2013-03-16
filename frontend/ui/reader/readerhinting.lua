
ReaderHinting = EventListener:new{
	hinting_states = {}
}

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