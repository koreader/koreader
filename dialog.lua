require "widget"
require "font"

InfoMessage = {
	face = Font:getFace("infofont", 25)
}

function InfoMessage:show(text,refresh_mode)
	Debug("# InfoMessage ", text, refresh_mode)
	local dialog = CenterContainer:new({
		dimen = { w = G_width, h = G_height },
		FrameContainer:new({
			margin = 2,
			background = 0,
			HorizontalGroup:new({
				align = "center",
				ImageWidget:new({
					file = "resources/info-i.png"
				}),
				Widget:new({
					dimen = { w = 10, h = 0 }
				}),
				TextWidget:new({
					text = text,
					face = Font:getFace("cfont", 30)
				})
			})
		})
	})
	dialog:paintTo(fb.bb, 0, 0)
	dialog:free()
	if refresh_mode ~= nil then
		fb:refresh(refresh_mode)
	end
end

function showInfoMsgWithDelay(text, msec, refresh_mode)
	if not refresh_mode then refresh_mode = 0 end
	Screen:saveCurrentBB()

	InfoMessage:show(text)
	fb:refresh(refresh_mode)
	-- util.usleep(msec*1000)
	
	-- eat the first key release event
	local ev = input.waitForEvent()
	adjustKeyEvents(ev)
	repeat
		ok = pcall( function()
			ev = input.waitForEvent(msec*1000)
			adjustKeyEvents(ev)
		end)
	until not ok or ev.value == EVENT_VALUE_KEY_PRESS

	Screen:restoreFromSavedBB()
	fb:refresh(refresh_mode)
end
