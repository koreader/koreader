local setmetatable, tonumber, tostring =
      setmetatable, tonumber, tostring
local floor, inf =
      math.floor, math.huge
local mininteger, tointeger =
      math.mininteger or nil, math.tointeger or nil
local byte, char, find, gsub, match, sub =
      string.byte, string.char, string.find, string.gsub, string.match, string.sub

local function _decode_error(pos, errmsg)
	error("parse error at " .. pos .. ": " .. errmsg, 2)
end

local f_str_ctrl_pat
if _VERSION == "Lua 5.1" then
	-- use the cluttered pattern because lua 5.1 does not handle \0 in a pattern correctly
	f_str_ctrl_pat = '[^\32-\255]'
else
	f_str_ctrl_pat = '[\0-\31]'
end

local _ENV = nil


local function newdecoder()
	local json, pos, nullv, arraylen, rec_depth

	-- `f` is the temporary for dispatcher[c] and
	-- the dummy for the first return value of `find`
	local dispatcher, f

	--[[
		Helper
	--]]
	local function decode_error(errmsg)
		return _decode_error(pos, errmsg)
	end

	--[[
		Invalid
	--]]
	local function f_err()
		decode_error('invalid value')
	end

	--[[
		Constants
	--]]
	-- null
	local function f_nul()
		if sub(json, pos, pos+2) == 'ull' then
			pos = pos+3
			return nullv
		end
		decode_error('invalid value')
	end

	-- false
	local function f_fls()
		if sub(json, pos, pos+3) == 'alse' then
			pos = pos+4
			return false
		end
		decode_error('invalid value')
	end

	-- true
	local function f_tru()
		if sub(json, pos, pos+2) == 'rue' then
			pos = pos+3
			return true
		end
		decode_error('invalid value')
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
		return decode_error('invalid number')
	end

	-- `0(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_zro(mns)
		local num, c = match(json, '^(%.?[0-9]*)([-+.A-Za-z]?)', pos)  -- skipping 0

		if num == '' then
			if c == '' then
				if mns then
					return -0.0
				end
				return 0
			end

			if c == 'e' or c == 'E' then
				num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
				if c == '' then
					pos = pos + #num
					if mns then
						return -0.0
					end
					return 0.0
				end
			end
			number_error()
		end

		if byte(num) ~= 0x2E or byte(num, -1) == 0x2E then
			number_error()
		end

		if c ~= '' then
			if c == 'e' or c == 'E' then
				num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
			end
			if c ~= '' then
				number_error()
			end
		end

		pos = pos + #num
		c = fixedtonumber(num)

		if mns then
			c = -c
		end
		return c
	end

	-- `[1-9][0-9]*(\.[0-9]*)?([eE][+-]?[0-9]*)?`
	local function f_num(mns)
		pos = pos-1
		local num, c = match(json, '^([0-9]+%.?[0-9]*)([-+.A-Za-z]?)', pos)
		if byte(num, -1) == 0x2E then  -- error if ended with period
			number_error()
		end

		if c ~= '' then
			if c ~= 'e' and c ~= 'E' then
				number_error()
			end
			num, c = match(json, '^([^eE]*[eE][-+]?[0-9]+)([-+.A-Za-z]?)', pos)
			if not num or c ~= '' then
				number_error()
			end
		end

		pos = pos + #num
		c = fixedtonumber(num)

		if mns then
			c = -c
			if c == mininteger and not find(num, '[^0-9]') then
				c = mininteger
			end
		end
		return c
	end

	-- skip minus sign
	local function f_mns()
		local c = byte(json, pos)
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
		decode_error('invalid number')
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
			decode_error("invalid escape sequence")
		end
	}
	setmetatable(f_str_escapetbl, f_str_escapetbl)

	local function surrogate_first_error()
		return decode_error("1st surrogate pair byte not continued by 2nd")
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
					decode_error("2nd surrogate pair byte appeared without 1st")
				end
			end
			decode_error("invalid unicode codepoint literal")
		end
		if f_str_surrogate_prev ~= 0 then
			f_str_surrogate_prev = 0
			surrogate_first_error()
		end
		return f_str_escapetbl[ch] .. ucode
	end

	-- caching interpreted keys for speed
	local f_str_keycache = setmetatable({}, {__mode="v"})

	local function f_str(iskey)
		local newpos = pos
		local tmppos, c1, c2
		repeat
			newpos = find(json, '"', newpos, true)  -- search '"'
			if not newpos then
				decode_error("unterminated string")
			end
			tmppos = newpos-1
			newpos = newpos+1
			c1, c2 = byte(json, tmppos-1, tmppos)
			if c2 == 0x5C and c1 == 0x5C then  -- skip preceding '\\'s
				repeat
					tmppos = tmppos-2
					c1, c2 = byte(json, tmppos-1, tmppos)
				until c2 ~= 0x5C or c1 ~= 0x5C
				tmppos = newpos-2
			end
		until c2 ~= 0x5C  -- leave if '"' is not preceded by '\'

		local str = sub(json, pos, tmppos)
		pos = newpos

		if iskey then  -- check key cache
			tmppos = f_str_keycache[str]  -- reuse tmppos for cache key/val
			if tmppos then
				return tmppos
			end
			tmppos = str
		end

		if find(str, f_str_ctrl_pat) then
			decode_error("unescaped control string")
		end
		if find(str, '\\', 1, true) then  -- check whether a backslash exists
			-- We need to grab 4 characters after the escape char,
			-- for encoding unicode codepoint to UTF-8.
			-- As we need to ensure that every first surrogate pair byte is
			-- immediately followed by second one, we grab upto 5 characters and
			-- check the last for this purpose.
			str = gsub(str, '\\(.)([^\\]?[^\\]?[^\\]?[^\\]?[^\\]?)', f_str_subst)
			if f_str_surrogate_prev ~= 0 then
				f_str_surrogate_prev = 0
				decode_error("1st surrogate pair byte not continued by 2nd")
			end
		end
		if iskey then  -- commit key cache
			f_str_keycache[tmppos] = str
		end
		return str
	end

	--[[
		Arrays, Objects
	--]]
	-- array
	local function f_ary()
		rec_depth = rec_depth + 1
		if rec_depth > 1000 then
			decode_error('too deeply nested json (> 1000)')
		end
		local ary = {}

		pos = match(json, '^[ \n\r\t]*()', pos)

		local i = 0
		if byte(json, pos) == 0x5D then  -- check closing bracket ']' which means the array empty
			pos = pos+1
		else
			local newpos = pos
			repeat
				i = i+1
				f = dispatcher[byte(json,newpos)]  -- parse value
				pos = newpos+1
				ary[i] = f()
				newpos = match(json, '^[ \n\r\t]*,[ \n\r\t]*()', pos)  -- check comma
			until not newpos

			newpos = match(json, '^[ \n\r\t]*%]()', pos)  -- check closing bracket
			if not newpos then
				decode_error("no closing bracket of an array")
			end
			pos = newpos
		end

		if arraylen then -- commit the length of the array if `arraylen` is set
			ary[0] = i
		end
		rec_depth = rec_depth - 1
		return ary
	end

	-- objects
	local function f_obj()
		rec_depth = rec_depth + 1
		if rec_depth > 1000 then
			decode_error('too deeply nested json (> 1000)')
		end
		local obj = {}

		pos = match(json, '^[ \n\r\t]*()', pos)
		if byte(json, pos) == 0x7D then  -- check closing bracket '}' which means the object empty
			pos = pos+1
		else
			local newpos = pos

			repeat
				if byte(json, newpos) ~= 0x22 then  -- check '"'
					decode_error("not key")
				end
				pos = newpos+1
				local key = f_str(true)  -- parse key

				-- optimized for compact json
				-- c1, c2 == ':', <the first char of the value> or
				-- c1, c2, c3 == ':', ' ', <the first char of the value>
				f = f_err
				local c1, c2, c3 = byte(json, pos, pos+3)
				if c1 == 0x3A then
					if c2 ~= 0x20 then
						f = dispatcher[c2]
						newpos = pos+2
					else
						f = dispatcher[c3]
						newpos = pos+3
					end
				end
				if f == f_err then  -- read a colon and arbitrary number of spaces
					newpos = match(json, '^[ \n\r\t]*:[ \n\r\t]*()', pos)
					if not newpos then
						decode_error("no colon after a key")
					end
					f = dispatcher[byte(json, newpos)]
					newpos = newpos+1
				end
				pos = newpos
				obj[key] = f()  -- parse value
				newpos = match(json, '^[ \n\r\t]*,[ \n\r\t]*()', pos)
			until not newpos

			newpos = match(json, '^[ \n\r\t]*}()', pos)
			if not newpos then
				decode_error("no closing bracket of an object")
			end
			pos = newpos
		end

		rec_depth = rec_depth - 1
		return obj
	end

	--[[
		The jump table to dispatch a parser for a value,
		indexed by the code of the value's first char.
		Nil key means the end of json.
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
		__index = function()
			decode_error("unexpected termination")
		end
	}
	setmetatable(dispatcher, dispatcher)

	--[[
		run decoder
	--]]
	local function decode(json_, pos_, nullv_, arraylen_)
		json, pos, nullv, arraylen = json_, pos_, nullv_, arraylen_
		rec_depth = 0

		pos = match(json, '^[ \n\r\t]*()', pos)

		f = dispatcher[byte(json, pos)]
		pos = pos+1
		local v = f()

		if pos_ then
			return v, pos
		else
			f, pos = find(json, '^[ \n\r\t]*', pos)
			if pos ~= #json then
				decode_error('json ended')
			end
			return v
		end
	end

	return decode
end

return newdecoder
