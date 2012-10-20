require "widget"
require "font"

-- some definitions for developers
MSG_AUX = 1
MSG_WARN = 2
MSG_ERROR = 3
MSG_CONFIRM = 4
MSG_BUG = 5

InfoMessage = {
	InfoMethod = { --[[ 
		The items define how to inform user about various types of events, the values should be 0..3:
			the lowest bit is responcible for showing popup windows,
			while the 2nd bit allows using TTS-voice messages.
		The current default values {1,1,1,1,1} correspond to previous kpdfviewer-settings
		when every message is shown in popup window. ]]
	1,	-- auxiliary messages = 0 or 2 (nothing or TTS)
	1,	-- warnings = 1 or 2 (popup or TTS)
	1,	-- errors = 1 or 3 (popup or popup & TTS)
	1,	-- confirmations (must not be silent!) = 1 or 3 (popup or popup & TTS)
	1,	-- bugs (must not be silent!) = 1 or 3 (popup or popup & TTS)
	},
	-- images for various message types
	Images = {
		"resources/info-aux.png",
		"resources/info-warn.png",
		"resources/info-error.png",
		"resources/info-confirm.png",
		"resources/info-bug.png",
		}, 
	ImageFile = "resources/info-warn.png",
	-- TTS-related parameters
	TTSspeed = nil,
	SoundVolume = nil,

	--[[ as Kindle3-volume has nonlinear scale, one need to define the 'VolumeLevels'-values
		TODO: test whether VolumeLevels are different for other sound-equipped Kindle models (K2, KDX)
		by running self.VolumeLevels = self:getVolumeLevels() ]]
	VolumeLevels = { 0, 1, 2, 4, 6, 7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77}
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
					file = self.ImageFile
				}),
				Widget:new({
					dimen = { w = 10, h = 0 }
				}),
				TextWidget:new({
					text = text,
					face = Font:getFace("infofont", 30)
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

--[[ Unified function to inform user about smth. It is generally intended to replace showInfoMsgWithDelay() & InfoMessage:show().
Since the former function is used in Lua-code more often than the latter, I kept here the same sequence of parameters as used in
showInfoMsgWithDelay() + added two not obligatory parameters (see description below).

Thus, this trick allows multiple text replaces thoughout the whole Lua-code: 'showInfoMsgWithDelay(' to 'InfoMessage:inform('
Yet, it would be much better to accompany such replaces by adding the 'message_importance' and, if needed, by
'alternative_voice_message' that is not so restricted in length as 'text'

But replacing InfoMessage:show(...) by InfoMessage:inform(...) MUST be accompanied by adding the 2nd parameter -- either msec=nil or msec=0.
Adding new parameters -- 'message_importance' & 'alternative_voice_message' -- is also appreciated.

Brief description of the function parameters
-- text : is the text message for visual and (if 'alternative_voice_message' isn't defined) voice notification
-- msec : parameter to define visual notification method
	msec=0: one calls InfoMessage:show(), otherwise one calls showInfoMsgWithDelay()
	msec>0: with either predefines msec-value or
	msec<0: autocalculated from the text length: one may eventually add user-configurable 
		parameter 'reading_speed' that would define the popup exposition for this regime
-- message_importance : parameter separating various messages on
	1 - not obligatory messages that might be readily avoided
	2 - warnings (important messages)
	3 - errors
	4 - confirmations
	5 - bugs
-- alternative_voice_message: not obligatory parameter that allows to send longer messages to TTS-engine
	if not defined, the default 'text' will be TTS-voiced
]]

function InfoMessage:inform(text, msec, refresh_mode, message_importance, alternative_voice_message)
	-- temporary test for 'message_importance'; it might be further removed as soon
	-- as every message will be properly marked by 'importance'
	if not message_importance then message_importance = 5 end
	local popup, voice = InfoMessage:getMethodForEvent(message_importance)
	if voice then
		alternative_voice_message = alternative_voice_message or text
		say(alternative_voice_message)
		-- here one may set pause -- it might be useful only if one sound message
		-- is directly followed by another, otherwise it's just wasting of time.
		--[[ if msec and msec ~=0 then
			-- pause = 0.5sec + 40ms/character * string.len() / normalized_voice_speed
			util.usleep(500000 + 40*alternative_voice_message:len*10000/self.TTSspeed)
		end ]]
	end
	if not popup then return end -- to avoid drawing popup window
	self.ImageFile = self.Images[message_importance] -- select proper image for window
	if not msec or msec == 0 then
		InfoMessage:show(text, refresh_mode)
	else
		if msec < 0 then msec = 500 + string.len(text) * 50 end
		showInfoMsgWithDelay(text, msec, refresh_mode)
	end
end

function InfoMessage:getMethodForEvent(event)
	local popup, voice = true, true
	if self.InfoMethod[event] %2 == 0 then popup = false end
	if self.InfoMethod[event] < 2 then voice = false end
	return popup, voice
end

-- GUI-methods for user to choose the way to inform about various events --

function InfoMessage:chooseMethodForEvent(event)
	local popup, voice = self:getMethodForEvent(event)
	local items_menu = SelectMenu:new{
		menu_title = "Choose the way how to inform you",
		item_array = {"Avoid any notifications", 
					"Show popup window",
					"Use TTS-voice",
					"Popup window and TTS-voice",
					},
		current_entry = (popup and 1 or 0) + (voice and 1 or 0) * 2,
		}
	local item_no = items_menu:choose(0, fb.bb:getHeight())
	if item_no then
		self.InfoMethod[event] = item_no - 1
		-- just to illustrate the way how the selected method works; might be removed
		-- self:inform("Event = "..event..", Method = "..self.InfoMethod[event], -1500, 1, event,
		--	"You have chosen the method number "..self.InfoMethod[event].." for the event item number "..event)
	end
end

function InfoMessage:chooseEventForMethod(event)
	event = event or 0
	local item_no = 0
	local event_list = {
		"Messages (e.g. 'Scanning folder...')",
		"Warnings (e.g. 'Already first jump!')",
		"Errors (e.g. 'Zip contains improper content!')",
		"Confirmations (e.g. 'Press Y to confirm deleting')",
		"Bugs",
		}
	while item_no ~= event and item_no < #event_list do
		item_no = item_no + 1 
	end
	local event_menu = SelectMenu:new{
		menu_title = "Select the event type to tune",
		item_array = event_list,
		current_entry = item_no - 1,
		}
	item_no = event_menu:choose(0, G_height)
	return item_no
end

function InfoMessage:chooseNotificatonMethods()
	local event = 1 -- default: auxiliary messages
	while event do
		event = self:chooseEventForMethod(event)
		if event then self:chooseMethodForEvent(event) end
	end
end

---------------- audio-related functions ----------------

function InfoMessage:incrTTSspeed(direction) -- either +1 or -1
	-- make sure new TTS-speed is within reasonable range
	self.TTSspeed = math.max(self.TTSspeed + direction * 20, 40) -- min = 40%
	self.TTSspeed = math.min(self.TTSspeed, 200) -- max = 200%
	-- set new value & give an example for more convenient tuning
	os.execute('lipc-set-prop com.lab126.tts TtsISpeed '..self.TTSspeed)
	say("The current voice speed is "..self.TTSspeed.." percent.")
end

function InfoMessage:getTTSspeed()
	if util.isEmulated() == 1 then
		return 0
	end
	local tmp = io.popen('lipc-get-prop com.lab126.tts TtsISpeed', "r")
	local speed = tmp:read("*number")
	tmp:close()
	return speed or 100 -- nominal TTS-speed
end

function InfoMessage:incrSoundVolume(direction) -- either +1 or -1
	-- make sure that new volume is within reasonable range
	self.SoundVolume = math.max(self.SoundVolume + direction, 1)
	self.SoundVolume = math.min(self.SoundVolume, #self.VolumeLevels)
	-- set new value & give an example for more convenient tuning
	os.execute('lipc-set-prop com.lab126.audio Volume '..(self.SoundVolume-1))
	-- that is not exactly the volume percents, but more conventional values,
	-- than abstract units returned by 'lipc-get-prop com.lab126.audio Volume'
	local percents = math.floor(100*self.VolumeLevels[self.SoundVolume]/self.VolumeLevels[#self.VolumeLevels])
	say("The current sound volume is "..percents.." percent.")
end

function InfoMessage:getSoundVolume()
	if util.isEmulated() == 1 then
		return 0
	end
	local tmp = io.popen('lipc-get-prop com.lab126.audio Volume', "r")
	local volume = tmp:read("*number")
	tmp:close()
	local i = 1
	while self.VolumeLevels[i] < volume and i < #self.VolumeLevels do
		i = i + 1
	end
	return i or 16 -- maximum volume
end

--[[ -- to determine self.VolumeLevels in various Kindle-models
function InfoMessage:getVolumeLevels()
	local levels, v, i = {}, 0, 0
	while i < 16 do -- proper K3-range 0..15 might be different for other models
		os.execute('lipc-set-prop com.lab126.audio Volume '..i)
		v = self:getSoundVolume()
		table.insert(levels, v) 
		i = i + 1
	end
	return levels
end	]]

function say(text)
	if util.isEmulated() == 1 then
		os.execute("espeak \""..text.."\"")
	else
		os.execute("say \""..text.."\"")
	end
end

-- The read/write global InfoMessage settings. When properly tested, the
-- condition 'if FileChooser.filemanager_expert_mode == ...' might be deleted

function InfoMessage:initInfoMessageSettings()
	if FileChooser.filemanager_expert_mode == FileChooser.ROOT_MODE then
		InfoMessage.InfoMethod = G_reader_settings:readSetting("info_message_methods") or InfoMessage.InfoMethod
		InfoMessage.TTSspeed = G_reader_settings:readSetting("tts_speed") or InfoMessage:getTTSspeed()
		InfoMessage.SoundVolume = G_reader_settings:readSetting("sound_volume") or InfoMessage:getSoundVolume()
	end
end

function InfoMessage:saveInfoMessageSettings()
	if FileChooser.filemanager_expert_mode == FileChooser.ROOT_MODE then
		G_reader_settings:saveSetting("info_message_methods", InfoMessage.InfoMethod)
		G_reader_settings:saveSetting("sound_volume", InfoMessage.SoundVolume-1)
		G_reader_settings:saveSetting("tts_speed", InfoMessage.TTSspeed)
	end
end
