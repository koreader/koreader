#!./kpdfview
--[[
    KindlePDFViewer: a reader implementation
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

require "alt_getopt"
require "keys"
require "tilecache"

ZOOM_BY_VALUE = 0
ZOOM_FIT_TO_PAGE = -1
ZOOM_FIT_TO_PAGE_WIDTH = -2
ZOOM_FIT_TO_PAGE_HEIGHT = -3
ZOOM_FIT_TO_CONTENT = -4
ZOOM_FIT_TO_CONTENT_WIDTH = -5
ZOOM_FIT_TO_CONTENT_HEIGHT = -6

GAMMA_NO_GAMMA = -1.0

-- option parsing:
longopts = {
	password = "p",
	goto = "g",
	gamma = "G",
	device = "d",
	help = "h"
}
optarg, optind = alt_getopt.get_opts(ARGV, "p:G:hg:d:", longopts)
if optarg["h"] or ARGV[optind] == nil then
	print("usage: ./reader.lua [OPTION] ... DOCUMENT.PDF")
	print("Read PDFs on your E-Ink reader")
	print("")
	print("-p, --password=PASSWORD   set password for reading PDF document")
	print("-g, --goto=page           start reading on page")
	print("-G, --gamma=GAMMA         set gamma correction")
	print("                          (floating point notation, e.g. \"1.5\")")
	print("-d, --device=DEVICE       set device specific configuration,")
	print("                          currently one of \"kdxg\" (default), \"k3\"")
	print("-h, --help                show this usage help")
	print("")
	print("This software is licensed under the GPLv3.")
	print("See http://github.com/hwhw/kindlepdfviewer for more info.")
	return
end

rcount = 5
rcountmax = 5

globalzoom = 1.0
globalzoommode = ZOOM_FIT_TO_PAGE
globalgamma = GAMMA_NO_GAMMA

fullwidth = 0
fullheight = 0

shiftmode = false

if optarg["d"] == "k3" then
	-- for now, the only difference is the additional input device
	input.open("/dev/input/event0")
	input.open("/dev/input/event1")
	input.open("/dev/input/event2")
	set_k3_keycodes()
elseif optarg["d"] == "emu" then
	input.open("")
	-- SDL key codes
	set_emu_keycodes()
else
	input.open("/dev/input/event0")
	input.open("/dev/input/event1")
end

if optarg["G"] ~= nil then
	globalgamma = optarg["G"]
end

doc = pdf.openDocument(ARGV[optind], optarg["p"] or "")

print("pdf has "..doc:getPages().." pages.")

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

nulldc = pdf.newDC()

function setzoom(page, cacheslot)
	local dc = pdf.newDC()
	local pwidth, pheight = page:getSize(nulldc)
	local offset_x = 0
	local offset_y = 0

	if globalzoommode == ZOOM_FIT_TO_PAGE then
		globalzoom = width / pwidth
		offset_x = 0
		offset_y = (height - (globalzoom * pheight)) / 2
		if height / pheight < globalzoom then
			globalzoom = height / pheight
			offset_x = (width - (globalzoom * pwidth)) / 2
			offset_y = 0
		end
	elseif globalzoommode == ZOOM_FIT_TO_PAGE_WIDTH then
		globalzoom = width / pwidth
		offset_x = 0
		offset_y = (height - (globalzoom * pheight)) / 2
	elseif globalzoommode == ZOOM_FIT_TO_PAGE_HEIGHT then
		globalzoom = height / pheight
		offset_x = (width - (globalzoom * pwidth)) / 2
		offset_y = 0
	elseif globalzoommode == ZOOM_FIT_TO_CONTENT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		globalzoom = width / (x1 - x0)
		offset_x = -1 * x0 * globalzoom
		offset_y = -1 * y0 * globalzoom + (height - (globalzoom * (y1 - y0))) / 2
		if height / (y1 - y0) < globalzoom then
			globalzoom = height / (y1 - y0)
			offset_x = -1 * x0 * globalzoom + (width - (globalzoom * (x1 - x0))) / 2
			offset_y = -1 * y0 * globalzoom
		end
	elseif globalzoommode == ZOOM_FIT_TO_CONTENT_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		globalzoom = width / (x1 - x0)
		offset_x = -1 * x0 * globalzoom
		offset_y = -1 * y0 * globalzoom + (height - (globalzoom * (y1 - y0))) / 2
	elseif globalzoommode == ZOOM_FIT_TO_CONTENT_HEIGHT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		globalzoom = height / (y1 - y0)
		offset_x = -1 * x0 * globalzoom + (width - (globalzoom * (x1 - x0))) / 2
		offset_y = -1 * y0 * globalzoom
	end
	dc:setZoom(globalzoom)
	dc:setOffset(offset_x, offset_y)
	fullwidth, fullheight = page:getSize(dc)

	-- set gamma here, we don't have any other good place for this right now:
	if globalgamma ~= GAMMA_NO_GAMMA then
		print("gamma correction: "..globalgamma)
		dc:setGamma(globalgamma)
	end
	return dc
end

function show(no)
	local slot
	if globalzoommode ~= ZOOM_BY_VALUE then
		slot = draworcache(no,globalzoommode,0,0,width,height,globalgamma)
	else
		slot = draworcache(no,globalzoom,0,0,width,height,globalgamma)
	end
	fb:blitFullFrom(cache[slot].bb)
	if rcount == rcountmax then
		print("full refresh")
		rcount = 1
		fb:refresh(0)
	else
		print("partial refresh")
		rcount = rcount + 1
		fb:refresh(1)
	end
	slot_visible = slot;
end

function goto(no)
	if no < 1 or no > doc:getPages() then
		return
	end
	pageno = no
	show(no)
	if no < doc:getPages() then
		-- always pre-cache next page
		if globalzoommode ~= ZOOM_BY_VALUE then
			draworcache(no,globalzoommode,0,0,width,height,globalgamma)
		else
			draworcache(no,globalzoom,0,0,width,height,globalgamma)
		end
	end
end

function modify_gamma(offset)
	if globalgamma == -1 then
		globalgamma = 1
	end
	print("modify_gamma, gamma="..globalgamma.." offset="..offset)
	globalgamma = globalgamma + offset;
	goto(pageno)
end
function setglobalzoommode(newzoommode)
	if globalzoommode ~= newzoommode then
		globalzoommode = newzoommode
		goto(pageno)
	end
end
function setglobalzoom(zoom)
	if globalzoom ~= zoom then
		globalzoommode = ZOOM_BY_VALUE
		globalzoom = zoom
		goto(pageno)
	end
end

function mainloop()
	while 1 do
		local ev = input.waitForEvent()
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			if ev.code == KEY_SHIFT then
				shiftmode = true
			elseif ev.code == KEY_PGFWD then
				if not shiftmode then
					goto(pageno + 1)
				else
					setglobalzoom(globalzoom*1.25)
				end
			elseif ev.code == KEY_PGBCK then
				if not shiftmode then
					goto(pageno - 1)
				else
					setglobalzoom(globalzoom*0.8)
				end
			elseif ev.code == KEY_BACK then
				return
			elseif ev.code == KEY_FW_UP then
				modify_gamma( 0.2 )
			elseif ev.code == KEY_FW_DOWN then
				modify_gamma( -0.2 )
			elseif ev.code == KEY_A then
				if shiftmode then
					setglobalzoommode(ZOOM_FIT_TO_CONTENT)
				else
					setglobalzoommode(ZOOM_FIT_TO_PAGE)
				end
			elseif ev.code == KEY_S then
				if shiftmode then
					setglobalzoommode(ZOOM_FIT_TO_CONTENT_WIDTH)
				else
					setglobalzoommode(ZOOM_FIT_TO_PAGE_WIDTH)
				end
			elseif ev.code == KEY_D then
				if shiftmode then
					setglobalzoommode(ZOOM_FIT_TO_CONTENT_HEIGHT)
				else
					setglobalzoommode(ZOOM_FIT_TO_PAGE_HEIGHT)
				end
			end
			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		elseif ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_RELEASE and ev.code == KEY_SHIFT then
			shiftmode = false
		end
	end
end

goto(tonumber(optarg["g"]) or 1)

mainloop()
