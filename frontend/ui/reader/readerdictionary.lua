local EventListener = require("ui/widget/eventlistener")
local UIManager = require("ui/uimanager")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local JSON = require("JSON")
local DEBUG = require("dbg")

local ReaderDictionary = EventListener:new{}

function ReaderDictionary:onLookupWord(highlight, word, box)
	self.highlight = highlight
	self:stardictLookup(word, box)
end

function ReaderDictionary:stardictLookup(word, box)
	DEBUG("lookup word:", word, box)
	if word then
		-- strip punctuation characters around selected word
		word = string.gsub(word, "^%p+", '')
		word = string.gsub(word, "%p+$", '')
		DEBUG("stripped word:", word)
		-- escape quotes and other funny characters in word
		local std_out = io.popen("./sdcv --utf8-input --utf8-output -nj "..("%q"):format(word), "r")
		local results_str = nil
		if std_out then results_str = std_out:read("*all") end
		if results_str then
			--DEBUG("result str:", word, results_str)
			local ok, results = pcall(JSON.decode, JSON, results_str)
			--DEBUG("lookup result table:", word, results)
			self:showDict(results, box)
		end
	end
end

function ReaderDictionary:showDict(results, box)
	if results and results[1] then
		DEBUG("showing quick lookup dictionary window")
		local align = nil
		local region = Geom:new{x = 0, w = Screen:getWidth()}
		if box.y + box.h/2 < Screen:getHeight()/2 then
			region.y = box.y + box.h
			region.h = Screen:getHeight() - box.y - box.h
			align = "top"
		else
			region.y = 0
			region.h = box.y
			align = "bottom"
		end
		UIManager:show(DictQuickLookup:new{
			ui = self.ui,
			highlight = self.highlight,
			dialog = self.dialog,
			results = results,
			dictionary = self.default_dictionary,
			width = Screen:getWidth() - Screen:scaleByDPI(80),
			height = math.min(region.h*0.7, Screen:getHeight()*0.5),
			region = region,
			align = align,
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

function ReaderDictionary:onSaveSettings()
	self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
