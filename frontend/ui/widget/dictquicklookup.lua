local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local LineWidget = require("ui/widget/linewidget")
local Screen = require("ui/screen")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("ui/device")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")

--[[
Display quick lookup word definition
]]
local DictQuickLookup = InputContainer:new{
	results = nil,
	lookupword = nil,
	dictionary = nil,
	definition = nil,
	dict_index = 1,
	title_face = Font:getFace("tfont", 22),
	word_face = Font:getFace("tfont", 20),
	content_face = Font:getFace("cfont", 20),
	width = nil,
	height = nil,
	
	title_padding = Screen:scaleByDPI(5),
	title_margin = Screen:scaleByDPI(2),
	word_padding = Screen:scaleByDPI(2),
	word_margin = Screen:scaleByDPI(2),
	definition_padding = Screen:scaleByDPI(2),
	definition_margin = Screen:scaleByDPI(2),
	button_padding = Screen:scaleByDPI(14),
}

function DictQuickLookup:init()
	self:changeToDefaultDict()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapCloseDict = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				},
			},
			Swipe = {
				GestureRange:new{
					ges = "swipe",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				},
			},
		}
	end
end

function DictQuickLookup:update()
	-- dictionary title
	self.dict_title = FrameContainer:new{
		padding = self.title_padding,
		margin = self.title_margin,
		bordersize = 0,
		TextWidget:new{
			text = self.dictionary,
			face = self.title_face,
			width = self.width,
		}
	}
	-- lookup word
	local lookup_word = FrameContainer:new{
		padding = self.word_padding,
		margin = self.word_margin,
		bordersize = 0,
		TextBoxWidget:new{
			text = self.lookupword,
			face = self.word_face,
			width = self.width,
		},
	}
	-- word definition
	local definition = FrameContainer:new{
		padding = self.definition_padding,
		margin = self.definition_margin,
		bordersize = 0,
		ScrollTextWidget:new{
			text = self.definition,
			face = self.content_face,
			width = self.width,
			height = self.height*0.8,
			dialog = self,
		},
	}	
	local button_table = ButtonTable:new{
		width = math.max(self.width, definition:getSize().w),
		button_font_face = "cfont",
		button_font_size = 20,
		buttons = {
			{	
				{
					text = _("<<"),
					enabled = self:isPrevDictAvaiable(),
					callback = function()
						self:changeToPrevDict()
					end,
				},
				{
					text = _(">>"),
					enabled = self:isNextDictAvaiable(),
					callback = function()
						self:changeToNextDict()
					end,
				},
			},
			{
				{
					text = _("Highlight"),
					enabled = false,
					callback = function()
						self.ui:handleEvent(Event:new("Highlight"))
					end,
				},
				{
					text = _("Add Note"),
					enabled = false,
					callback = function()
						self.ui:handleEvent(Event:new("AddNote"))
					end,
				},
			},
		},
		zero_sep = true,
	}
	local title_bar = LineWidget:new{
		--background = 8,
		dimen = Geom:new{
			w = button_table:getSize().w + self.button_padding,
			h = Screen:scaleByDPI(2),
		}
	}
	
	self.dict_frame = FrameContainer:new{
		radius = 8,
		bordersize = 3,
		padding = 0,
		margin = 0,
		background = 0,
		VerticalGroup:new{
			align = "left",
			self.dict_title,
			title_bar,
			-- word
			CenterContainer:new{
				dimen = Geom:new{
					w = title_bar:getSize().w,
					h = lookup_word:getSize().h,
				},
				lookup_word,
			},
			-- definition
			CenterContainer:new{
				dimen = Geom:new{
					w = title_bar:getSize().w,
					h = definition:getSize().h,
				},
				definition,
			},
			-- buttons
			CenterContainer:new{
				dimen = Geom:new{
					w = title_bar:getSize().w,
					h = button_table:getSize().h,
				},
				button_table,
			}
		}
	}
	
	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		self.dict_frame,
	}
	UIManager.repaint_all = true
	UIManager.full_refresh = true
end

function DictQuickLookup:isPrevDictAvaiable()
	return self.dict_index > 1
end

function DictQuickLookup:isNextDictAvaiable()
	return self.dict_index < #self.results
end

function DictQuickLookup:changeToPrevDict()
	self:changeDictionary(self.dict_index - 1)
end

function DictQuickLookup:changeToNextDict()
	self:changeDictionary(self.dict_index + 1)
end

function DictQuickLookup:changeDictionary(index)
	self.dict_index = index
	self.dictionary = self.results[index].dict
	self.lookupword = self.results[index].word
	self.definition = self.results[index].definition
	
	local orig_dimen = self.dict_frame and self.dict_frame.dimen or Geom:new{}
	self:update()

	UIManager.update_region_func = function()
		local update_region = self.dict_frame.dimen:combine(orig_dimen)
		DEBUG("update region", update_region)
		return update_region
	end
end

function DictQuickLookup:changeToDefaultDict()		
	if self.dictionary then
		-- dictionaries that have definition of the first word(accurate word)
		-- excluding Fuzzy queries.
		local n_accurate_dicts = nil
		local default_word = self.results[1].word
		for i=1, #self.results do
			if self.results[i].word == default_word then
				n_accurate_dicts = i
			else
				break
			end
		end
		-- change to dictionary specified by self.dictionary
		for i=1, n_accurate_dicts do
			if self.results[i].dict == self.dictionary then
				self:changeDictionary(i)
				break
			end
			-- cannot find definition in default dictionary
			if i == n_accurate_dicts then
				self:changeDictionary(1)
			end
		end
	else
		self:changeDictionary(1)
	end
end

function DictQuickLookup:onAnyKeyPressed()
	-- triggered by our defined key events
	UIManager:close(self)
	return true
end

function DictQuickLookup:onTapCloseDict(arg, ges_ev)
	if ges_ev.pos:notIntersectWith(self.dict_frame.dimen) then
		UIManager:close(self)
		self.ui:handleEvent(Event:new("Tap"))
		return true
	elseif not ges_ev.pos:notIntersectWith(self.dict_title.dimen) then
		self.ui:handleEvent(Event:new("UpdateDefaultDict", self.dictionary))
		return true
	end
	return true
end

return DictQuickLookup
