require "widget"
require "font"

InfoMessage = {
	face = Font:getFace("infofont", 25)
}

function InfoMessage:show(text)
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
end

function showInfoMsgWithDelay(text, msec, refresh_mode)
	if not refresh_mode then refresh_mode = 0 end
	Screen:saveCurrentBB()

	InfoMessage:show(text)
	fb:refresh(refresh_mode)
	util.usleep(msec*1000)

	Screen:restoreFromSavedBB()
	fb:refresh(refresh_mode)
end
