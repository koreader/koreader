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

input.open("/dev/input/event0")
input.open("/dev/input/event1")

KEY_PAGE_UP = 109
KEY_PAGE_DOWN = 124

KEY_BACK = 91
KEY_MENU = 139

-- DPad:
KEY_UP = 122
KEY_DOWN = 123
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_BTN = 92

if ARGV[1] == nil then
	print("needs PDF filename as first argument.")
end
if ARGV[2] == nil then
	ARGV[2] = ""
end

rcount = 5
rcountmax = 5

globalzoom = -1

doc = pdf.openDocument(ARGV[1], ARGV[2])

print("pdf has "..doc:getPages().." pages.")

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

nulldc = pdf.newDC()

cache = {
	{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil },
	{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil },
	{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil }
}
function freecache()
	for i = 1, #cache do
		if cache[i].page ~= nil then
			print("freeing slot="..i.." oldpage="..cache[i].no)
			cache[i].page:close()
			cache[i].page = nil
		end
	end
end
function checkcache(no)
	for i = 1, #cache do
		if cache[i].no == no then
			print("cache hit: slot="..i.." page="..no)
			return i
		end
	end
	print("cache miss")
	return nil
end
function cacheslot()
	freeslot = nil
	while freeslot == nil do
		for i = 1, #cache do
			if cache[i].age > 0 then
				print("aging slot="..i)
				cache[i].age = cache[i].age - 1
			else
				if cache[i].page ~= nil then
					print("freeing slot="..i.." oldpage="..cache[i].no)
					cache[i].page:close()
					cache[i].page = nil
				end
				freeslot = i
			end
		end
	end
	print("returning free slot="..freeslot)
	return freeslot
end

function draworcache(no)
	local slot = checkcache(no)
	if slot == nil then
		slot = cacheslot()
		cache[slot].no = no
		cache[slot].age = #cache
		cache[slot].page = doc:openPage(no)
		setzoom(slot)
		print("drawing page="..no.." to slot="..slot)
		cache[slot].page:draw(cache[slot].dc, cache[slot].bb, 0, 0)
	end
	return slot
end

function setzoom(cacheslot)
	local pwidth, pheight = cache[cacheslot].page:getSize(nulldc)

	-- default zoom: fit to page
	local zoom = width / pwidth
	local offset_x = 0
	local offset_y = (height - (zoom * pheight)) / 2
	if height / pheight < zoom then
		zoom = height / pheight
		offset_x = (width - (zoom * pwidth)) / 2
		offset_y = 0
	end

	cache[cacheslot].dc:setZoom(zoom)
	cache[cacheslot].dc:setOffset(offset_x, offset_y)
end

function show(no)
	local slot = draworcache(no)
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
end

function goto(no)
	if no < 1 or no > doc:getPages() then
		return
	end
	pageno = no
	show(no)
	if no < doc:getPages() then
		-- always pre-cache next page
		draworcache(no+1)
	end
end

function mainloop()
	while 1 do
		local events = input.waitForEvent()
		for _, ev in ipairs(events) do
			if ev.type == 1 and (ev.value == 1 or ev.value == 2) then
				local secs, usecs = util.gettime()
				if ev.code == KEY_PAGE_DOWN then
					print(cache)
					goto(pageno + 1)
					print(cache)
				elseif ev.code == KEY_PAGE_UP then
					print(cache)
					goto(pageno - 1)
					print(cache)
				elseif ev.code == KEY_BACK then
					return
				end
				local nsecs, nusecs = util.gettime()
				local dur = (nsecs - secs) * 1000000 + nusecs - usecs
				print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
			end
		end
	end
end

goto(1)

mainloop()
