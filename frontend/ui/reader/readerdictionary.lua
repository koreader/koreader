require "ui/device"
require "ui/widget/dict"

ReaderDictionary = EventListener:new{}

function ReaderDictionary:init()
	local dev_mod = Device:getModel()
	if dev_mod == "KindlePaperWhite" or dev_mod == "KindleTouch" then
		require("liblipclua")
		DEBUG("init lipc handler com.github.koreader.dictionary")
		self.lipc_handle = lipc.init("com.github.koreader.dictionary")
	end
	JSON = require("JSON")
end

function ReaderDictionary:onLookupWord(word)
	self:stardictLookup(word)
end

function ReaderDictionary:nativeDictLookup(word)
	DEBUG("lookup word:", word)
	--self:quickLookup()
	if self.lipc_handle and word then
		self.lipc_handle:set_string_property(
			"com.github.koreader.kpvbooklet.dict", "lookup", word)
		local results_str = self.lipc_handle:get_string_property(
			"com.github.koreader.kpvbooklet.word", word)
		if results_str then
			--DEBUG("result str:", word, results_str)
			local ok, results_tab = pcall(JSON.decode, JSON, results_str)
			--DEBUG("lookup result table:", word, results_tab)
			if results_tab and results_tab[1] then
				self:showDict(results_tab[1])
			end
		end
	end
end

function ReaderDictionary:stardictLookup(word)
	DEBUG("lookup word:", word)
	if word then
		local std_out = io.popen("./sdcv -nj "..'\"'..word..'\"', "r")
		local results_str = std_out:read("*all")
		if results_str then
			--DEBUG("result str:", word, results_str)
			local ok, results_tab = pcall(JSON.decode, JSON, results_str)
			--DEBUG("lookup result table:", word, results_tab)
			if results_tab and results_tab[1] then
				self:showDict(results_tab[1])
			end
		end
	end
end

function ReaderDictionary:showDict(result)
--	UIManager:show(DictQuickLookup:new{
--		dict = "Oxford Dictionary of English",
--		definition = "coordination n. [mass noun] 1 the organization of the different elements of a \
--			complex body or activity so as to enable them to work together effectively: an important managerial \
--			task is the control and coordination of activities. cooperative effort resulting in an effective \
--			relationship: action groups work in coordination with local groups to end rainforest destruction. \
--			the ability to use different parts of the body together smoothly and efficiently: changing from \
--			one foot position to another requires coordination and balance.",
--		id = "/mnt/us/documents/dictionaries/Oxford_Dictionary_of_English.azw",
--		lang = "en",
--	})
	if result then 
		UIManager:show(DictQuickLookup:new{
			dict = result.dict,
			definition = result.definition,
			id = result.ID,
			lang = result.lang,
		})
	end
end
