require "ui"

-- we create a widget that paints a background:
Background = InputContainer:new{
	is_always_active = true, -- receive events when other dialogs are active
	key_events = {
		OpenDialog = { { "Press" } },
		OpenConfirmBox = { { "Del" } },
		QuitApplication = { { {"Home","Back"} } }
	},
	-- contains a gray rectangular desktop
	FrameContainer:new{
		background = 3,
		bordersize = 0,
		dimen = { w = G_width, h = G_height }
	}
}

function Background:onOpenDialog()
	UIManager:show(InfoMessage:new{
		text = "Example message.",
		timeout = 10
	})
end

function Background:onOpenConfirmBox()
	UIManager:show(ConfirmBox:new{
		text = "Please confirm delete"
	})
end

function Background:onInputError()
	UIManager:quit()
end

function Background:onQuitApplication()
	UIManager:quit()
end



-- example widget: a clock
Clock = FrameContainer:new{
	background = 0,
	bordersize = 1,
	margin = 0,
	padding = 1
}

function Clock:schedFunc()
	self[1]:free()
	self[1] = self:getTextWidget()
	UIManager:setDirty(self)
	-- reschedule
	-- TODO: wait until next real minute shift
	UIManager:scheduleIn(60, function() self:schedFunc() end)
end

function Clock:onShow()
	self[1] = self:getTextWidget()
	self:schedFunc()
end

function Clock:getTextWidget()
	return CenterContainer:new{
		dimen = { w = 300, h = 25 },
		TextWidget:new{
			text = os.date("%H:%M"),
			face = Font:getFace("cfont", 12)
		}
	}
end


UIManager:show(Background:new())
UIManager:show(Clock:new())
UIManager:run()
