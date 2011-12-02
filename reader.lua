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

GAMMA_NO_GAMMA = 1.0

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
offset_x = 0
offset_y = 0

shift_x = 100
shift_y = 50
pan_by_page = false -- using shift_[xy] or width/height

shiftmode = false
altmode = false

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
docdb, errno, errstr = sqlite3.open(ARGV[optind]..".kpdfview")
if docdb == nil then
	print(errstr)
else
	docdb:exec("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);")
	stmt_readsetting = docdb:prepare("SELECT value FROM settings WHERE key = ?;")
	stmt_savesetting = docdb:prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?);")
end

print("pdf has "..doc:getPages().." pages.")

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

nulldc = pdf.newDC()

function readsetting(key)
	if docdb ~= nil then
		stmt_readsetting:reset()
		stmt_readsetting:bind_values(key)
		result = stmt_readsetting:step()
		if result == sqlite3.ROW then
			return stmt_readsetting:get_value(0)
		end
	end
end

function savesetting(key, value)
	if docdb ~= nil then
		stmt_savesetting:reset()
		stmt_savesetting:bind_values(key, value)
		stmt_savesetting:step()
	end
end

function setzoom(page, cacheslot)
	local dc = pdf.newDC()
	local pwidth, pheight = page:getSize(nulldc)

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
		slot = draworcache(no,globalzoommode,offset_x,offset_y,width,height,globalgamma)
	else
		slot = draworcache(no,globalzoom,offset_x,offset_y,width,height,globalgamma)
	end
	fb.bb:blitFullFrom(cache[slot].bb)
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
			draworcache(no,globalzoommode,offset_x,offset_y,width,height,globalgamma)
		else
			draworcache(no,globalzoom,offset_x,offset_y,width,height,globalgamma)
		end
	end
end

function modify_gamma(factor)
	print("modify_gamma, gamma="..globalgamma.." factor="..factor)
	globalgamma = globalgamma * factor;
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
			elseif ev.code == KEY_ALT then
				altmode = true
			elseif ev.code == KEY_PGFWD then
				if shiftmode then
					setglobalzoom(globalzoom*1.2)
				elseif altmode then
					setglobalzoom(globalzoom*1.1)
				else
					goto(pageno + 1)
				end
			elseif ev.code == KEY_PGBCK then
				if shiftmode then
					setglobalzoom(globalzoom*0.8)
				elseif altmode then
					setglobalzoom(globalzoom*0.9)
				else
					goto(pageno - 1)
				end
			elseif ev.code == KEY_BACK then
				if docdb ~= nil then
					savesetting("last_page", pageno)
					docdb:close()
				end
				return
			elseif ev.code == KEY_VPLUS then
				modify_gamma( 1.25 )
			elseif ev.code == KEY_VMINUS then
				modify_gamma( 0.8 )
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

			if globalzoommode == ZOOM_BY_VALUE then
				local x
				local y

				if shiftmode then -- shift always moves in small steps
					x = shift_x / 2
					y = shift_y / 2
				elseif altmode then
					x = shift_x / 5
					y = shift_y / 5
				elseif pan_by_page then
					x = width  - 5; -- small overlap when moving by page
					y = height - 5;
				else
					x = shift_x
					y = shift_y
				end

				print("offset "..offset_x.."*"..offset_x.." shift "..x.."*"..y.." globalzoom="..globalzoom)

				if ev.code == KEY_FW_LEFT then
					offset_x = offset_x + x
					goto(pageno)
				elseif ev.code == KEY_FW_RIGHT then
					offset_x = offset_x - x
					goto(pageno)
				elseif ev.code == KEY_FW_UP then
					offset_y = offset_y + y
					goto(pageno)
				elseif ev.code == KEY_FW_DOWN then
					offset_y = offset_y - y
					goto(pageno)
				elseif ev.code == KEY_FW_PRESS then
					if shiftmode then
						offset_x = 0
						offset_y = 0
						goto(pageno)
					else
						pan_by_page = not pan_by_page
					end
				end
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		elseif ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_RELEASE and ev.code == KEY_SHIFT then
			shiftmode = false
		elseif ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_RELEASE and ev.code == KEY_ALT then
			altmode = false
		end
	end
end

goto(tonumber(optarg["g"]) or tonumber(readsetting("last_page") or 1))

mainloop()
