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
require "pdfreader"
require "djvureader"
require "filechooser"
require "settings"

-- option parsing:
longopts = {
	password = "p",
	goto = "g",
	gamma = "G",
	device = "d",
	help = "h"
}

function openFile(filename)
	local file_type = string.lower(string.match(filename, ".+%.(.+)"))
	if file_type == "djvu" then
		print "haha"
		if DJVUReader:open(filename) then
			page_num = DJVUReader.settings:readsetting("last_page") or 1
			DJVUReader:goto(tonumber(page_num))
			DJVUReader:inputloop()
		end
	elseif file_type == "pdf" then
		if PDFReader:open(filename,"") then -- TODO: query for password
			page_num = PDFReader.settings:readsetting("last_page") or 1
			PDFReader:goto(tonumber(page_num))
			PDFReader:inputloop()
		end
	end
end

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
	print("                          \"emu\" (DXG emulation)")
	print("-h, --help                show this usage help")
	print("")
	print("If you give the name of a directory instead of a path, a file")
	print("chooser will show up and let you select a PDF file")
	print("")
	print("This software is licensed under the GPLv3.")
	print("See http://github.com/hwhw/kindlepdfviewer for more info.")
	return
end


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

	-- check if we are running on Kindle 3 (additional volume input)
	local f=lfs.attributes("/dev/input/event2")
	print(f)
	if f then
		print("Auto-detected Kindle 3")
		input.open("/dev/input/event2")
		set_k3_keycodes()
	end

end

if optarg["G"] ~= nil then
	globalgamma = optarg["G"]
end

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

-- set up reader's setting: font
reader_settings = DocSettings:open(".reader")
r_cfont = reader_settings:readsetting("cfont")
if r_cfont ~=nil then
	FontChooser.cfont = r_cfont
end

-- initialize specific readers
PDFReader:init()
DJVUReader:init()

-- display directory or open file
if lfs.attributes(ARGV[optind], "mode") == "directory" then
	local running = true
	FileChooser:setPath(ARGV[optind])
	while running do
		local file = FileChooser:choose(0,height)
		if file ~= nil then
			openFile(file)
		else
			running = false
		end
	end
else
	openFile(ARGV[optind], optarg["p"])
end


-- save reader settings
reader_settings:savesetting("cfont", FontChooser.cfont)
reader_settings:close()

input.closeAll()
--os.execute('test -e /proc/keypad && echo "send '..KEY_HOME..'" > /proc/keypad ')
if optarg["d"] ~= "emu" then
	os.execute('echo "send '..KEY_MENU..'" > /proc/keypad;echo "send '..KEY_MENU..'" > /proc/keypad')
end
