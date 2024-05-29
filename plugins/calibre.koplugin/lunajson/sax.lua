local setmetatable, tonumber, tostring =
      setmetatable, tonumber, tostring
local floor, inf =
      math.floor, math.huge
local mininteger, tointeger =
      math.mininteger or nil, math.tointeger or nil
local byte, char, find, gsub, match, sub =
      string.byte, string.char, string.find, string.gsub, string.match, string.sub

local function _parse_error(pos, errmsg)
	error("parse error at " .. pos .. ": " .. errmsg, 2)
end

local f_str_ctrl_pat
if _VERSION == "Lua 5.1" then
	-- use the cluttered pattern because lua 5.1 does not handle \0 in a pattern correctly
	f_str_ctrl_pat = '[^\32-\255]'
else
	f_str_ctrl_pat = '[\0-\31]'
end

local type, unpack = type, table.unpack or unpack
local open = io.open

local _ENV = nil


local function nop() end

local function newparser(src, saxtbl)
	local json, jsonnxt, rec_depth
	local jsonlen, pos, acc = 0, 1, 0

	-- `f` is the temporary for dispatcher[c] and
	-- the dummy for the first return value of `find`
	local dispatcher, f

	-- initialize
	if type(src) == 'string' then
		json = src
		jsonlen = #json
		jsonnxt = function()
			json = ''
			jsonlen = 0
			jsonnxt = nop
		end
	else
		jsonnxt = function()
			acc = acc + jsonlen
			pos = 1
			repeat
				json = src()
				if not json then
					json = ''
					jsonlen = 0
					jsonnxt = nop
					return
				end
				jsonlen = #json
			until jsonlen > 0
		end
		jsonnxt()
	end

	local sax_startobject = saxtbl.startobject or nop
	local sax_key = saxtbl.key or nop
	local sax_endobject = saxtbl.endobject or nop
	local sax_startarray = saxtbl.startarray or nop
	local sax_endarray = saxtbl.endarray or nop
	local sax_string = saxtbl.string or nop
	local sax_number = saxtbl.number or nop
	local sax_boolean = saxtbl.boolean or nop
	local sax_null = saxtbl.null or nop

	--[[
		Helper
	--]]
	local function tryc()
		local c = byte(json, pos)
		if not c then
			jsonnxt()
			c = byte(json, pos)
		end
		return c
	end

	local function parse_error(errmsg)
		return _parse_error(acc + pos, errmsg)
	end

	local function tellc()
		return tryc() or parse_error("unexpected termination")
	end

	local function spaces()  -- skip spaces and prepare the next char
		while true do
			pos = match(json, '^[ \n\r\t]*()', pos)
			if pos <= jsonlen then
				return
			end
			if jsonlen == 0 then
				parse_error("unexpected termination")
			end
			jsonnxt()
		end
	end

	--[[
		Invalid
	--]]
	local function f_err()
		parse_error('invalid value')
	end

	--[[
		Constants
	--]]
	-- fallback slow constants parser
	local function generic_constant(target, targetlen, ret, sax_f)
		for i = 1, targetlen do
			local c = tellc()
			if byte(target, i) ~= c then
				parse_error("invalid char")
			end
			pos = pos+1
		end
		return sax_f(ret)
	end

	-- null
	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return sax_null(nil)
		end
		return generic_constant('ull', 3, nil, sax_null)
	end

	-- false
	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return sax_boolean(false)
		end
		return generic_constant('alse', 4, false, sax_boolean)
	end

	-- true
	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return sax_boolean(true)
		end
		return generic_constant('rue', 3, true, sax_boolean)
	end

	--[[
		Numbers
		Conceptually, the longest prefix that matches to `[-+.0-9A-Za-z]+` (in regexp)
		is captured as a number and its conformance to the JSON spec is checked.
	--]]
	-- deal with non-standard locales
	local radixmark = match(tostring(0.5), '[^0-9]')
	local fixedtonumber = tonumber
	if radixmark ~= '.' then
		if find(radixmark, '%W') then
			radixmark = '%' .. radixmark
		end
		fixedtonumber = function(s)
			return tonumber(gsub(s, '.', radixmark))
		end
	end

	local function number_error()
		return parse_error('invalid number')
	end

	-- fallback slow parser
	local function generic_number(mns)
		local buf = {}
		local i = 1
		local is_int = true

		local c = byte(json, pos)
		pos = pos+1

		local function nxt()
			buf[i] = c
			i = i+1
			c = tryc()
			pos = pos+1
		end

		if c == 0x30 then
			nxt()
			if c and 0x30 <= c and c < 0x3A then
				number_error()
			end
		else
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		if c == 0x2E then
			is_int = false
			nxt()
			if not (c and 0x30 <= c and c < 0x3A) then
				number_error()
			end
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		if c == 0x45 or c == 0x65 then
			is_int = false
			nxt()
			if c == 0x2B or c == 0x2D then
				nxt()
			end
			if not (c and 0x30 <= c and c < 0x3A) then
				number_error()
			end
			repeat nxt() until not (c and 0x30 <= c and c < 0x3A)
		end
		if c and (0x41 <= c and c <= 0x5B or
		          0x61 <= c and c <= 0x7B or
		          c == 0x2B or c == 0x2D or c == 0x2E) then
			number_error()
		end
		pos = pos-1

		local num = char(unpack(buf))
		num = fixedtonumber(num)
		if mns then
			num = -num
			if num == mininteger and is_int then
				num = mininteger
			end
		end
		return sax_number(num)
	end

	-- `0(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_zro(mns)
		local num, c = match(json, '^(%.?[0-9]*)([-+.A-Za-z]?)', pos)  -- skipping 0

		if num == '' then
			if pos > jsonlen then
				pos = pos - 1
				return generic_number(mns)
			end
			if c == '' then
				if mns then
					return sax_number(-0.0)
				end
				return sax_number(0)
			end

			if c == 'e' or c == 'E' then
				num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
				if c == '' then
					pos = pos + #num
					if pos > jsonlen then
						pos = pos - #num - 1
						return generic_number(mns)
					end
					if mns then
						return sax_number(-0.0)
					end
					return sax_number(0.0)
				end
			end
			pos = pos-1
			return generic_number(mns)
		end

		if byte(num) ~= 0x2E or byte(num, -1) == 0x2E then
			pos = pos-1
			return generic_number(mns)
		end

		if c ~= '' then
			if c == 'e' or c == 'E' then
				num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
			end
			if c ~= '' then
				pos = pos-1
				return generic_number(mns)
			end
		end

		pos = pos + #num
		if pos > jsonlen then
			pos = pos - #num - 1
			return generic_number(mns)
		end
		c = fixedtonumber(num)

		if mns then
			c = -c
		end
		return sax_number(c)
	end

	-- `[1-9][0-9]*(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_num(mns)
		pos = pos-1
		local num, c = match(json, '^([0-9]+%.?[0-9]*)([-+.A-Za-z]?)', pos)
		if byte(num, -1) == 0x2E then  -- error if ended with period
			return generic_number(mns)
		end

		if c ~= '' then
			if c ~= 'e' and c ~= 'E' then
				return generic_number(mns)
			end
			num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
			if not num or c ~= '' then
				return generic_number(mns)
			end
		end

		pos = pos + #num
		if pos > jsonlen then
			pos = pos - #num
			return generic_number(mns)
		end
		c = fixedtonumber(num)

		if mns then
			c = -c
			if c == mininteger and not find(num, '[^0-9]') then
				c = mininteger
			end
		end
		return sax_number(c)
	end

	-- skip minus sign
	local function f_mns()
		local c = byte(json, pos) or tellc()
		if c then
			pos = pos+1
			if c > 0x30 then
				if c < 0x3A then
					return f_num(true)
				end
			else
				if c > 0x2F then
					return f_zro(true)
				end
			end
		end
		parse_error("invalid number")
	end

	--[[
		Strings
	--]]
	local f_str_hextbl = {
		0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
		0x8, 0x9, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, inf, inf, inf, inf, inf, inf, inf,
		inf, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF,
		__index = function()
			return inf
		end
	}
	setmetatable(f_str_hextbl, f_str_hextbl)

	local f_str_escapetbl = {
		['"']  = '"',
		['\\'] = '\\',
		['/']  = '/',
		['b']  = '\b',
		['f']  = '\f',
		['n']  = '\n',
		['r']  = '\r',
		['t']  = '\t',
		__index = function()
			parse_error("invalid escape sequence")
		end
	}
	setmetatable(f_str_escapetbl, f_str_escapetbl)

	local function surrogate_first_error()
		return parse_error("1st surrogate pair byte not continued by 2nd")
	end

	local f_str_surrogate_prev = 0
	local function f_str_subst(ch, ucode)
		if ch == 'u' then
			local c1, c2, c3, c4, rest = byte(ucode, 1, 5)
			ucode = f_str_hextbl[c1-47] * 0x1000 +
			        f_str_hextbl[c2-47] * 0x100 +
			        f_str_hextbl[c3-47] * 0x10 +
			        f_str_hextbl[c4-47]
			if ucode ~= inf then
				if ucode < 0x80 then  -- 1byte
					if rest then
						return char(ucode, rest)
					end
					return char(ucode)
				elseif ucode < 0x800 then  -- 2bytes
					c1 = floor(ucode / 0x40)
					c2 = ucode - c1 * 0x40
					c1 = c1 + 0xC0
					c2 = c2 + 0x80
					if rest then
						return char(c1, c2, rest)
					end
					return char(c1, c2)
				elseif ucode < 0xD800 or 0xE000 <= ucode then  -- 3bytes
					c1 = floor(ucode / 0x1000)
					ucode = ucode - c1 * 0x1000
					c2 = floor(ucode / 0x40)
					c3 = ucode - c2 * 0x40
					c1 = c1 + 0xE0
					c2 = c2 + 0x80
					c3 = c3 + 0x80
					if rest then
						return char(c1, c2, c3, rest)
					end
					return char(c1, c2, c3)
				elseif 0xD800 <= ucode and ucode < 0xDC00 then  -- surrogate pair 1st
					if f_str_surrogate_prev == 0 then
						f_str_surrogate_prev = ucode
						if not rest then
							return ''
						end
						surrogate_first_error()
					end
					f_str_surrogate_prev = 0
					surrogate_first_error()
				else  -- surrogate pair 2nd
					if f_str_surrogate_prev ~= 0 then
						ucode = 0x10000 +
						        (f_str_surrogate_prev - 0xD800) * 0x400 +
						        (ucode - 0xDC00)
						f_str_surrogate_prev = 0
						c1 = floor(ucode / 0x40000)
						ucode = ucode - c1 * 0x40000
						c2 = floor(ucode / 0x1000)
						ucode = ucode - c2 * 0x1000
						c3 = floor(ucode / 0x40)
						c4 = ucode - c3 * 0x40
						c1 = c1 + 0xF0
						c2 = c2 + 0x80
						c3 = c3 + 0x80
						c4 = c4 + 0x80
						if rest then
							return char(c1, c2, c3, c4, rest)
						end
						return char(c1, c2, c3, c4)
					end
					parse_error("2nd surrogate pair byte appeared without 1st")
				end
			end
			parse_error("invalid unicode codepoint literal")
		end
		if f_str_surrogate_prev ~= 0 then
			f_str_surrogate_prev = 0
			surrogate_first_error()
		end
		return f_str_escapetbl[ch] .. ucode
	end

	local function f_str(iskey)
		local pos2 = pos
		local newpos
		local str = ''
		local bs
		while true do
			while true do  -- search '\' or '"'
				newpos = find(json, '[\\"]', pos2)
				if newpos then
					break
				end
				str = str .. sub(json, pos, jsonlen)
				if pos2 == jsonlen+2 then
					pos2 = 2
				else
					pos2 = 1
				end
				jsonnxt()
				if jsonlen == 0 then
					parse_error("unterminated string")
				end
			end
			if byte(json, newpos) == 0x22 then  -- break if '"'
				break
			end
			pos2 = newpos+2  -- skip '\<char>'
			bs = true  -- mark the existence of a backslash
		end
		str = str .. sub(json, pos, newpos-1)
		pos = newpos+1

		if find(str, f_str_ctrl_pat) then
			parse_error("unescaped control string")
		end
		if bs then  -- a backslash exists
			-- We need to grab 4 characters after the escape char,
			-- for encoding unicode codepoint to UTF-8.
			-- As we need to ensure that every first surrogate pair byte is
			-- immediately followed by second one, we grab upto 5 characters and
			-- check the last for this purpose.
			str = gsub(str, '\\(.)([^\\]?[^\\]?[^\\]?[^\\]?[^\\]?)', f_str_subst)
			if f_str_surrogate_prev ~= 0 then
				f_str_surrogate_prev = 0
				parse_error("1st surrogate pair byte not continued by 2nd")
			end
		end

		if iskey then
			return sax_key(str)
		end
		return sax_string(str)
	end

	--[[
		Arrays, Objects
	--]]
	-- arrays
	local function f_ary()
		rec_depth = rec_depth + 1
		if rec_depth > 1000 then
			parse_error('too deeply nested json (> 1000)')
		end
		sax_startarray()

		spaces()
		if byte(json, pos) == 0x5D then  -- check closing bracket ']' which means the array empty
			pos = pos+1
		else
			local newpos
			while true do
				f = dispatcher[byte(json, pos)]  -- parse value
				pos = pos+1
				f()
				newpos = match(json, '^[ \n\r\t]*,[ \n\r\t]*()', pos)  -- check comma
				if newpos then
					pos = newpos
				else
					newpos = match(json, '^[ \n\r\t]*%]()', pos)  -- check closing bracket
					if newpos then
						pos = newpos
						break
					end
					spaces()  -- since the current chunk can be ended, skip spaces toward following chunks
					local c = byte(json, pos)
					pos = pos+1
					if c == 0x2C then  -- check comma again
						spaces()
					elseif c == 0x5D then  -- check closing bracket again
						break
					else
						parse_error("no closing bracket of an array")
					end
				end
				if pos > jsonlen then
					spaces()
				end
			end
		end

		rec_depth = rec_depth - 1
		return sax_endarray()
	end

	-- objects
	local function f_obj()
		rec_depth = rec_depth + 1
		if rec_depth > 1000 then
			parse_error('too deeply nested json (> 1000)')
		end
		sax_startobject()

		spaces()
		if byte(json, pos) == 0x7D then  -- check closing bracket '}' which means the object empty
			pos = pos+1
		else
			local newpos
			while true do
				if byte(json, pos) ~= 0x22 then
					parse_error("not key")
				end
				pos = pos+1
				f_str(true)  -- parse key
				newpos = match(json, '^[ \n\r\t]*:[ \n\r\t]*()', pos)  -- check colon
				if newpos then
					pos = newpos
				else
					spaces()  -- read spaces through chunks
					if byte(json, pos) ~= 0x3A then  -- check colon again
						parse_error("no colon after a key")
					end
					pos = pos+1
					spaces()
				end
				if pos > jsonlen then
					spaces()
				end
				f = dispatcher[byte(json, pos)]
				pos = pos+1
				f()  -- parse value
				newpos = match(json, '^[ \n\r\t]*,[ \n\r\t]*()', pos)  -- check comma
				if newpos then
					pos = newpos
				else
					newpos = match(json, '^[ \n\r\t]*}()', pos)  -- check closing bracket
					if newpos then
						pos = newpos
						break
					end
					spaces()  -- read spaces through chunks
					local c = byte(json, pos)
					pos = pos+1
					if c == 0x2C then  -- check comma again
						spaces()
					elseif c == 0x7D then  -- check closing bracket again
						break
					else
						parse_error("no closing bracket of an object")
					end
				end
				if pos > jsonlen then
					spaces()
				end
			end
		end

		rec_depth = rec_depth - 1
		return sax_endobject()
	end

	--[[
		The jump table to dispatch a parser for a value,
		indexed by the code of the value's first char.
		Key should be non-nil.
	--]]
	dispatcher = { [0] =
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_str, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_mns, f_err, f_err,
		f_zro, f_num, f_num, f_num, f_num, f_num, f_num, f_num,
		f_num, f_num, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_ary, f_err, f_err, f_err, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_fls, f_err,
		f_err, f_err, f_err, f_err, f_err, f_err, f_nul, f_err,
		f_err, f_err, f_err, f_err, f_tru, f_err, f_err, f_err,
		f_err, f_err, f_err, f_obj, f_err, f_err, f_err, f_err,
	}

	--[[
		public funcitons
	--]]
	local function run()
		rec_depth = 0
		spaces()
		f = dispatcher[byte(json, pos)]
		pos = pos+1
		f()
	end

	local function read(n)
		if n < 0 then
			error("the argument must be non-negative")
		end
		local pos2 = (pos-1) + n
		local str = sub(json, pos, pos2)
		while pos2 > jsonlen and jsonlen ~= 0 do
			jsonnxt()
			pos2 = pos2 - (jsonlen - (pos-1))
			str = str .. sub(json, pos, pos2)
		end
		if jsonlen ~= 0 then
			pos = pos2+1
		end
		return str
	end

	local function tellpos()
		return acc + pos
	end

	return {
		run = run,
		tryc = tryc,
		read = read,
		tellpos = tellpos,
	}
end

local function newfileparser(fn, saxtbl)
	local fp = open(fn)
	local function gen()
		local s
		if fp then
			s = fp:read(8192)
			if not s then
				fp:close()
				fp = nil
			end
		end
		return s
	end
	return newparser(gen, saxtbl)
end

return {
	newparser = newparser,
	newfileparser = newfileparser
}
