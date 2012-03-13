require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "selectmenu"
require "commands"

HelpPage = {
	-- Class vars:
	-- font for displaying keys
	fsize = 20,
	face = freetype.newBuiltinFace("mono", 20),
	fhash = "mono20",
	
	-- font for displaying help messages
	hfsize = 20,
	hface = freetype.newBuiltinFace("sans", 20),
	hfhash = "sans20",	

	-- font for paging display
	ffsize = 15,
	fface = freetype.newBuiltinFace("sans", 15),
	ffhash = "sans15",

	-- spacing between lines
	spacing = 25,

	-- state buffer
	commands = nil,
	items = 0,
	page = 1
}

function HelpPage:show(ypos, height,commands)
	self.commands = {}
	self.items = 0
	local keys = {}
	for k,v in pairs(commands.map) do
		local key = v.keygroup or v.keydef:display()
		--print("order: "..v.order.." command: "..tostring(v.keydef).." - keygroup:"..(v.keygroup or "nil").." -keys[key]:"..(keys[key] or "nil"))
		if keys[key] == nil then
			keys[key] = 1
			table.insert(self.commands,{shortcut=key,help=v.help,order=v.order})
			self.items = self.items + 1
		end
	end
	table.sort(self.commands,function(w1,w2) return w1.order<w2.order end)
	local perpage = math.floor( (height - 1 * (self.ffsize + 5)) / self.spacing )
	local pagedirty = true

	while true do
		if pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			local max_x = 0
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					local pen_x = renderUtf8Text(fb.bb, 5, ypos + self.spacing*c, self.face, self.fhash, self.commands[i].shortcut, true)
					max_x = math.max(max_x, pen_x)
				end
			end
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					renderUtf8Text(fb.bb, max_x + 20, ypos + self.spacing*c, self.hface, self.hfhash, self.commands[i].help, true)
				end
			end			
			renderUtf8Text(fb.bb, 5, height - math.floor(self.ffsize * 0.4), self.fface, self.ffhash,
				"Page "..self.page.." of "..math.ceil(self.items / perpage).."  - click Back to close this page", true)					
			markerdirty = true
		end
		if pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			pagedirty = false
		end

		local ev = input.waitForEvent()
		--print("key code:"..ev.code)
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_PGFWD then
				if self.page < (self.items / perpage) then
					self.page = self.page + 1
					pagedirty = true
				end
			elseif ev.code == KEY_PGBCK then
				if self.page > 1 then
					self.page = self.page - 1
					pagedirty = true
				end
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
