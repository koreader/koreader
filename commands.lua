require "keys"

Keydef = {}
Keydef.mt = {} 
function Keydef.new(keycode,modifier,descr)
	local keydef = {}
	keydef.keycode = keycode
	keydef.modifier = modifier
	keydef.descr = descr
	setmetatable(keydef, Keydef.mt)
	return keydef
end
function Keydef.tostring(keydef)
	return ((keydef.modifier and keydef.modifier.."+") or "").."["..(keydef.keycode or "").."]"..(keydef.descr or "")
end
function Keydef.concat(keydef, obj)
	if getmetatable(obj)==Keydef.mt then
		return tostring(keydef)..tostring(obj)
	else
		return tostring(keydef)..obj
	end
end
Keydef.mt.__tostring=Keydef.tostring
Keydef.mt.__concat=Keydef.concat

Command = {}
Command.mt = {} 
function Command.new(keydef, func, help)
	local command = {}
	command.keydef = keydef
	command.func = func
	command.help = help
	setmetatable(command, Command.mt)
	return command
end
function Command.tostring(command)
	return command.keydef..": "..command.help
end	
Command.mt.__tostring=Command.tostring


Commands = {
	map = {}
}
function Commands:add(keycode,modifier,keydescr,help,func)
	local keydef = Keydef.new(keycode, modifier,keydescr)
	self:_add_impl(keydef,help,func)
end	
function Commands:_add_impl(keydef,help,func,keygroup)
	local command = self.map[keydef]
	if command == nil then	
		command = Command.new(keydef,func,help)	
		self.map[keydef] = command
	else
		command.func = func
		command.help = help
		command.keygroup = keygroup
	end
end	
function Commands:add_group(keygroup,keys,help,func)
	for _k,keydef in pairs(keys) do
		self:_add_impl(keydef,help,func,keygroup)
	end
end	
function Commands:get(keycode,modifier)
	return self.map[Keydef.new(keycode, modifier)]
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