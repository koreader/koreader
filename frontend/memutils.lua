local ffi = require "ffi"
local bit = require "bit"
local band = bit.band
local bor = bit.bor
local rshift = bit.rshift
local lshift = bit.lshift




ffi.cdef[[
void * malloc ( size_t size );
void free ( void * ptr );
void * realloc ( void * ptr, size_t size );
]]

function bzero(dest, nbytes)
	ffi.fill(dest, nbytes)
	return dest
end

function bcopy(src, dest, nbytes)
	ffi.copy(dest, src, nbytes)
end

function bcmp(ptr1, ptr2, nbytes)
	for i=0,nbytes do
		if ptr1[i] ~= ptr2[i] then return -1 end
	end

	return 0
end



function memset(dest, c, len)
	ffi.fill(dest, len, c)
	return dest
end

function memcpy(dest, src, nbytes)
	ffi.copy(dest, src, nbytes)
end

function memcmp(ptr1, ptr2, nbytes)
	local p1 = ffi.cast("const uint8_t *", ptr1)
	local p2 = ffi.cast("const uint8_t *", ptr2)

	for i=0,nbytes do
		if p1[i] ~= p2[i] then return -1 end
	end

	return 0
end

function memchr(ptr, value, num)
	local p = ffi.cast("const uint8_t *", ptr)
	for i=0,num-1 do
		if p[i] == value then return p+i end
	end

	return nil
end

function memmove(dst, src, num)
	local srcptr = ffi.cast("const uint8_t*", src)

	-- If equal, just return
	if dst == srcptr then return dst end


	if srcptr < dst then
		-- copy from end
		for i=num-1,0, -1 do
			dst[i] = srcptr[i];
		end
	else
		-- copy from beginning
		for i=0,num-1 do
			dst[i] = srcptr[i];
		end
	end
	return dst
end

local function memreverse(buff, bufflen)
	local i = 0;
	local tmp

	while (i < (bufflen)/2) do
		tmp = buff[i];
		buff[i] = buff[bufflen-i-1];
		buff[bufflen-i-1] = tmp;

		i = i + 1;
	end
	return buff
end

local function getreverse(src, len)
	if not len then
		if type(src) == "string" then
			len = #src
		else
			return nil, "unknown length"
		end
	end

	local srcptr = ffi.cast("const uint8_t *", src);
	local dst = ffi.new("uint8_t[?]", len)

	for i = 0, len-1 do
		dst[i] = srcptr[len-1-i];
	end

	return dst, len
end

return {
	bcmp = bcmp,
	bcopy = bcopy,
	bzero = bzero,

	memchr = memchr,
	memcpy = memcpy,
	memcmp = memcmp,
	memmove = memmove,
	memset = memset,

	memreverse = memreverse,
}
