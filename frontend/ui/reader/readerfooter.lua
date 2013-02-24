
ReaderFooter = InputContainer:new{
	pageno = nil,
	pages = nil,
	progress_percentage = 0.0,
	progress_text = "0 / 0",
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
	local bar_containner = RightContainer:new{
		dimen = Geom:new{w = Screen:getWidth()*self.bar_width, h = self.height},
		self.progress_bar,
	}
	local text_containner = CenterContainer:new{
		dimen = Geom:new{w = Screen:getWidth()*self.text_width, h = self.height},
		self.progress_text,
	}
	table.insert(horizontal_group, bar_containner)
	table.insert(horizontal_group, text_containner)
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
end

function ReaderFooter:paintTo(bb, x, y)
	self[1]:paintTo(bb, x, y)
end

function ReaderFooter:updateFooter()
	self.progress_bar.percentage = self.pageno / self.pages
	self.progress_text.text = string.format("%d / %d", self.pageno, self.pages)
end

function ReaderFooter:onPageUpdate(pageno)
	self.pageno = pageno
	self.pages = self.view.document.info.number_of_pages
	self:updateFooter()
end
