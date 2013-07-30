require "ui/widget/container"
require "ui/widget/inputtext"

InputDialog = InputContainer:new{
	title = "",
	input = "",
	input_hint = "",
	buttons = nil,
	input_type = nil,
	
	width = nil,
	height = nil,
	
	title_face = Font:getFace("tfont", 22),
	input_face = Font:getFace("cfont", 20),
	
	title_padding = scaleByDPI(5),
	title_margin = scaleByDPI(2),
	input_padding = scaleByDPI(10),
	input_margin = scaleByDPI(10),
	button_padding = scaleByDPI(14),
}

function InputDialog:init()
	self.title = FrameContainer:new{
		padding = self.title_padding,
		margin = self.title_margin,
		bordersize = 0,
		TextWidget:new{
			text = self.title,
			face = self.title_face,
			width = self.width,
		}
	}
	self.input = InputText:new{
		text = self.input,
		hint = self.input_hint,
		face = self.input_face,
		width = self.width * 0.9,
		input_type = self.input_type,
		scroll = false,
		parent = self,
	}
	local button_table = ButtonTable:new{
		width = self.width,
		button_font_face = "cfont",
		button_font_size = 20,
		buttons = self.buttons,
		zero_sep = true,
	}
	local title_bar = LineWidget:new{
		--background = 8,
		dimen = Geom:new{
			w = button_table:getSize().w + self.button_padding,
			h = scaleByDPI(2),
		}
	}
	
	self.dialog_frame = FrameContainer:new{
		radius = 8,
		bordersize = 3,
		padding = 0,
		margin = 0,
		background = 0,
		VerticalGroup:new{
			align = "left",
			self.title,
			title_bar,
			-- input
			CenterContainer:new{
				dimen = Geom:new{
					w = title_bar:getSize().w,
					h = self.input:getSize().h,
				},
				self.input,
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
		dimen = Geom:new{
			w = Screen:getWidth(),
			h = Screen:getHeight() - self.input:getKeyboardDimen().h,
		},
		self.dialog_frame,
	}
	UIManager.repaint_all = true
	UIManager.full_refresh = true
end

function InputDialog:onShowKeyboard()
	self.input:onShowKeyboard()
end

function InputDialog:getInputText()
	return self.input:getText()
end

function InputDialog:onClose()
	self.input:onCloseKeyboard()
end
