--[[
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--

--[[
Codes for rotation modes:

1 for no rotation, 
2 for landscape with bottom on the right side of screen, etc.

		  3
   +--------------+
   | +----------+ |
   | |          | |
   | | Freedom! | |
   | |          | |  
   | |          | |  
 4 | |          | | 2
   | |          | |
   | |          | |
   | +----------+ |
   |              |
   |              |
   +--------------+
		  1
--]]


Screen = {
	rotation_modes = {"Up","Right","Down","Left"},
	cur_rotation_mode = 1,
}

-- @ orien: 1 for clockwise rotate, -1 for anti-clockwise
function Screen:screenRotate(orien)
	if orien == "clockwise" then
		orien = 1
	elseif orien == "anticlockwise" then
		orien = -1
	else
		return
	end

	fb:close()
	self.cur_rotation_mode = (self.cur_rotation_mode-1 + 1*orien)%4 + 1
	local mode = self.rotation_modes[self.cur_rotation_mode]
	os.execute("lipc-send-event -r 3 com.lab126.hal orientation"..mode)
	fb = einkfb.open("/dev/fb0")
end

function Screen:updateRotationMode()
	if KEY_FW_DOWN == 116 then -- in EMU mode always set to 1
		self.cur_rotation_mode = 1
	else
		orie_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_orientation", "r"))
		updown_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_upside_down", "r"))
		self.cur_rotation_mode = orie_fd:read() + (updown_fd:read() * 2) + 1
	end
end


