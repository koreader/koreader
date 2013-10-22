local EventListener = require("ui/widget/eventlistener")
local UIManager = require("ui/uimanager")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Screen = require("ui/screen")
local JSON = require("JSON")

local ReaderDictionary = EventListener:new{}

function ReaderDictionary:onLookupWord(word)
	self:stardictLookup(word)
end

function ReaderDictionary:stardictLookup(word)
	DEBUG("lookup word:", word)
	if word then
		-- strip punctuation characters around selected word
		word = string.gsub(word, "^%p+", '')
		word = string.gsub(word, "%p+$", '')
		DEBUG("stripped word:", word)
		-- escape quotes and other funny characters in word
		local std_out = io.popen("./sdcv -nj "..("%q"):format(word), "r")
		local results_str = std_out:read("*all")
		if results_str then
			--DEBUG("result str:", word, results_str)
			local ok, results = pcall(JSON.decode, JSON, results_str)
			--DEBUG("lookup result table:", word, results)
			self:showDict(results)
		end
	end
end

function ReaderDictionary:showDict(results)
	if results and results[1] then
		DEBUG("showing quick lookup dictionary window")
		UIManager:show(DictQuickLookup:new{
			ui = self.ui,
			dialog = self.dialog,
			results = results,
			dictionary = self.default_dictionary,
			width = Screen:getWidth() - screen:scaleByDPI(120),
			height = Screen:getHeight()*0.43,
		})
	end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
	DEBUG("make default dictionary:", dict)
	self.default_dictionary = dict
end

function ReaderDictionary:onReadSettings(config)
	self.default_dictionary = config:readSetting("default_dictionary")
end

function ReaderDictionary:onCloseDocument()
	self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
