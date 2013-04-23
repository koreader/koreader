require "ui/device"

ReaderDictionary = EventListener:new{}

function ReaderDictionary:init()
	local dev_mod = Device:getModel()
	if dev_mod == "KindlePaperWhite" or dev_mod == "KindleTouch" then
		require "liblipclua"
		self.lipc_handle = lipc.init("com.github.koreader.dictionary")
	end
end

function ReaderDictionary:onLookupWord(word)
	DEBUG("lookup word:", word)
	if self.lipc_handle then
		-- start indicator depends on pillow being enabled
		self.lipc_handle:set_string_property(
			"com.lab126.booklet.kpvbooklet.dict", "lookup", word)
		local definitions = self.lipc_handle:get_string_property(
			"com.lab126.booklet.kpvbooklet.word", word)
		DEBUG("definitions of word:", word, definitions)
	end
	return true
end
