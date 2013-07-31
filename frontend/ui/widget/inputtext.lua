require "ui/graphics"
require "ui/widget/text"
require "ui/widget/keyboard"
require "ui/widget/container"

InputText = InputContainer:new{
	text = "",
	hint = "demo hint",
	charlist = {}, -- table to store input string
	charpos = 1,
	input_type = nil,
	
	width = nil,
	height = nil,
	face = Font:getFace("cfont", 22),
	
	padding = 5,
	margin = 5,
	bordersize = 2,
	
	parent = nil, -- parent dialog that will be set dirty
	scroll = false,
}

function InputText:init()
	self:StringToCharlist(self.text)
	self:initTextBox()
	self:initKeyboard()
end

function InputText:initTextBox()
	local bgcolor = nil
	local fgcolor = nil
	if self.text == "" then
		self.text = self.hint
		bgcolor = 0.0
		fgcolor = 0.5
	else
		bgcolor = 0.0
		fgcolor = 1.0
	end
	local text_widget = nil
	if self.scroll then
		text_widget = ScrollTextWidget:new{
			text = self.text,
			face = self.face,
			bgcolor = bgcolor,
			fgcolor = fgcolor,
			width = self.width,
			height = self.height,
		}
	else
		text_widget = TextBoxWidget:new{
			text = self.text,
			face = self.face,
			bgcolor = bgcolor,
			fgcolor = fgcolor,
			width = self.width,
			height = self.height,
		}
	end
	self[1] = FrameContainer:new{
		bordersize = self.bordersize,
		padding = self.padding,
		margin = self.margin,
		text_widget,
	}
	self.dimen = self[1]:getSize()
end

function InputText:initKeyboard()
	local keyboard_layout = 2
	if self.input_type == "number" then
		keyboard_layout = 3
	end
	self.keyboard = VirtualKeyboard:new{
		layout = keyboard_layout,
		inputbox = self,
		width = Screen:getWidth(),
		height = math.max(Screen:getWidth(), Screen:getHeight())*0.33,
	}
end

function InputText:onShowKeyboard()
	UIManager:show(self.keyboard)
end

function InputText:onCloseKeyboard()
	UIManager:close(self.keyboard)
end

function InputText:getKeyboardDimen()
	return self.keyboard.dimen
end

function InputText:addChar(char)
	table.insert(self.charlist, self.charpos, char)
	self.charpos = self.charpos + 1
	self.text = self:CharlistToString()
	self:initTextBox()
	UIManager:setDirty(self.parent, "partial")
end

function InputText:delChar()
	if self.charpos == 1 then return end
	self.charpos = self.charpos - 1
	table.remove(self.charlist, self.charpos)
	self.text = self:CharlistToString()
	self:initTextBox()
	UIManager:setDirty(self.parent, "partial")
end

function InputText:getText()
	return self.text
end

function InputText:StringToCharlist(text)
	if text == nil then return end
	-- clear
	self.charlist = {}
	self.charpos = 1
	local prevcharcode, charcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		charcode = util.utf8charcode(uchar)
		if prevcharcode then -- utf8
			self.charlist[#self.charlist+1] = uchar
		end
		prevcharcode = charcode
	end
	self.text = self:CharlistToString()
	self.charpos = #self.charlist+1
end

function InputText:CharlistToString()
	local s, i = ""
	for i=1, #self.charlist do
		s = s .. self.charlist[i]
	end
	return s
end
