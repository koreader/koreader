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
require "filechooser"

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
end

if optarg["G"] ~= nil then
	globalgamma = optarg["G"]
end

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

if lfs.attributes(ARGV[optind], "mode") == "directory" then
	local running = true
	FileChooser:setPath(ARGV[optind])
	while running do
		local pdffile = FileChooser:choose(0,height)
		if pdffile ~= nil then
			if PDFReader:open(pdffile,"") then -- TODO: query for password
				PDFReader:goto(tonumber(PDFReader.settings:readsetting("last_page") or 1))
				PDFReader:inputloop()
			end
		else
			running = false
		end
	end
else
	PDFReader:open(ARGV[optind], optarg["p"])
	PDFReader:goto(tonumber(optarg["g"]) or tonumber(PDFReader.settings:readsetting("last_page") or 1))
	PDFReader:inputloop()
end
