local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local DEBUG = require("dbg")

local ReaderFooter = InputContainer:new{
	visible = true,
	pageno = nil,
	pages = nil,
	progress_percentage = 0.0,
	progress_text = "0 / 0",
	show_time = false,
	bar_width = 0.88,
	text_width = 0.12,
	text_font_face = "ffont",
	text_font_size = 14,
	height = 19,
}

function ReaderFooter:init()
	self.progress_bar = ProgressWidget:new{
		width = math.floor(Screen:getWidth()*(self.bar_width-0.02)),
		height = 7,
		percentage = self.progress_percentage,
	}
	self.progress_text = TextWidget:new{
		text = self.progress_text,
		face = Font:getFace(self.text_font_face, self.text_font_size),
	}
	local _, text_height = self.progress_text:getSize()
	local horizontal_group = HorizontalGroup:new{}
	local bar_container = RightContainer:new{
		dimen = Geom:new{w = Screen:getWidth()*self.bar_width, h = self.height},
		self.progress_bar,
	}
	local text_container = CenterContainer:new{
		dimen = Geom:new{w = Screen:getWidth()*self.text_width, h = self.height},
		self.progress_text,
	}
	table.insert(horizontal_group, bar_container)
	table.insert(horizontal_group, text_container)
	self[1] = BottomContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			horizontal_group,
			background = 0,
			bordersize = 0,
			padding = 0,
		}
	}
	self.dimen = self[1]:getSize()
	self.pageno = self.view.state.page
	self.pages = self.view.document.info.number_of_pages
	self:updateFooter()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapFooter = {
				GestureRange:new{
					ges = "tap",
					range = self[1]:contentRange(),
				},
			},
		}
	end
end

function ReaderFooter:updateFooter()
	self.progress_bar.percentage = self.pageno / self.pages
	if self.show_time then
		self.progress_text.text = os.date("%H:%M")
	else
		self.progress_text.text = string.format("%d / %d", self.pageno, self.pages)
	end
end

function ReaderFooter:onPageUpdate(pageno)
	self.pageno = pageno
	self.pages = self.view.document.info.number_of_pages
	self:updateFooter()
end

function ReaderFooter:onTapFooter(arg, gev)
	self.show_time = not self.show_time
	self:updateFooter()
	UIManager:setDirty(self.view.dialog)
	-- consume this tap when footer is visible
	if self.visible then
		return true
	end
end

return ReaderFooter
