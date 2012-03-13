require "keys"

Keydef = {
	keycode = nil,
	modifier = nil,
	descr = nil
}
function Keydef:_new(obj)
	-- obj definition
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
	self.__tostring=Keydef.tostring
	return obj	
end
function Keydef:new(keycode,modifier,descr)
	obj = Keydef:_new()
	obj.keycode = keycode
	obj.modifier = modifier
	obj.descr = descr	
	return obj	
end
function Keydef:display()
	return ((self.modifier and self.modifier.."+") or "")..(self.descr or "")
end
function Keydef:tostring()
	return ((self.modifier and self.modifier.."+") or "").."["..(self.keycode or "").."]"..(self.descr or "")
end

Command = {
	keydef = nil,
	keygroup = nil,
	func = nil,
	help = nil,
	order = nil
}
function Command:_new(obj)
	-- obj definition
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
	self.__tostring=Command.tostring
	return obj	
end
function Command:new(keydef, func, help, keygroup, order)
	obj = Command:_new()
	obj.keydef = keydef
	obj.func = func
	obj.help = help
	obj.keygroup = keygroup
	obj.order = order
	--print("creating command: ["..tostring(keydef).."] keygroup:["..(keygroup or "").."] help:"..help)
	return obj
end
function Command:tostring()
	return tostring(self.keydef)..": "..(self.help or "<no help defined>")
end


Commands = {
	map = {},
	size = 0
}
function Commands:add(keycode,modifier,keydescr,help,func)
	local keydef = Keydef:new(keycode,modifier,keydescr)
	self:_add_impl(keydef,help,func)
end	
function Commands:add_group(keygroup,keys,help,func)
	for _k,keydef in pairs(keys) do
		self:_add_impl(keydef,help,func,keygroup)
	end
end
function Commands:_add_impl(keydef,help,func,keygroup)
	if keydef.modifier==MOD_ANY then
		self:add_group(keygroup or keydef.descr,{Keydef:new(keydef.keycode,nil), Keydef:new(keydef.keycode,MOD_SHIFT), Keydef:new(keydef.keycode,MOD_ALT)},help,func)
	elseif keydef.modifier==MOD_SHIFT_OR_ALT then
		self:add_group(keygroup or (MOD_SHIFT.."|"..MOD_ALT.."+"..(keydef.descr or "")),{Keydef:new(keydef.keycode,MOD_SHIFT), Keydef:new(keydef.keycode,MOD_ALT)},help,func)
	else
		local command = self.map[keydef]
		if command == nil then
			self.size = self.size + 1
			command = Command:new(keydef,func,help,keygroup,self.size)				
			self.map[keydef] = command
		else
			command.func = func
			command.help = help
			command.keygroup = keygroup
		end
	end	
end	
function Commands:get(keycode,modifier)
	return self.map[Keydef:new(keycode, modifier)]
end
function Commands:get_by_keydef(keydef)
	return self.map[keydef]
end
function Commands:new(obj)
	-- payload
	local mt = {}
	setmetatable(self.map,mt)
	mt.__index=function (table, key)
		return rawget(table,(key.modifier or "").."@#@"..(key.keycode or ""))
	end	
	mt.__newindex=function (table, key, value)
		return rawset(table,(key.modifier or "").."@#@"..(key.keycode or ""),value)
	end		
	-- obj definition
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
