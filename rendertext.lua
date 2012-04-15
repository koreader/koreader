glyphcache_max_memsize = 256*1024 -- 256kB glyphcache
glyphcache_current_memsize = 0
glyphcache = {}
glyphcache_max_age = 4096
function glyphCacheClaim(size)
	if(size > glyphcache_max_memsize) then
		error("too much memory claimed")
		return false
	end
	while glyphcache_current_memsize + size > glyphcache_max_memsize do
		for k, _ in pairs(glyphcache) do
			if glyphcache[k].age > 0 then
				glyphcache[k].age = glyphcache[k].age - 1
			else
				glyphcache_current_memsize = glyphcache_current_memsize - glyphcache[k].size
				glyphcache[k] = nil
			end
		end
	end
	glyphcache_current_memsize = glyphcache_current_memsize + size
	return true
end
function getGlyph(face, facehash, charcode)
	local hash = glyphCacheHash(facehash, charcode)
	if glyphcache[hash] == nil then
		local glyph = face:renderGlyph(charcode)
		local size = glyph.bb:getWidth() * glyph.bb:getHeight() / 2 + 32
		glyphCacheClaim(size);
		glyphcache[hash] = {
			age = glyphcache_max_age,
			size = size,
			g = glyph
		}
	else
		glyphcache[hash].age = glyphcache_max_age
	end
	return glyphcache[hash].g
end
function glyphCacheHash(face, charcode)
	return face..'_'..charcode;
end
function clearGlyphCache()
	glyphcache = {}
end

function sizeUtf8Text(face, facehash, text, kerning)
	if text == nil then
		print("# sizeUtf8Text called without text");
		return
	end
	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local prevcharcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < buffer:getWidth() then
			local charcode = util.utf8charcode(uchar)
			local glyph = getglyph(face, facehash, charcode)
			if kerning and prevcharcode then
				local kern = face:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
				print("prev:"..string.char(prevcharcode+10).." curr:"..string.char(charcode).." kern:"..kern)
				buffer:addblitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			else
				print("curr:"..string.char(charcode))
				buffer:blitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			end
			pen_x = pen_x + glyph.ax
			prevcharcode = charcode
		end
	end
	return pen_x
end

function renderUtf8Text(buffer, x, y, face, facehash, text, kerning)
	if text == nil then
		print("# renderUtf8Text called without text");
		return
	end
	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local prevcharcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < buffer:getWidth() then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, facehash, charcode)
			if kerning and prevcharcode then
				local kern = face:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
				--print("prev:"..string.char(prevcharcode).." curr:"..string.char(charcode).." pen_x:"..pen_x.." kern:"..kern)
				buffer:addblitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			else
				--print(" curr:"..string.char(charcode))
				buffer:blitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			end
			pen_x = pen_x + glyph.ax
			prevcharcode = charcode
		end
	end
	return pen_x
end
