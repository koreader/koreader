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
				glyphcache[k].glyph.bb:free()
				glyphcache[k] = nil
			end
		end
	end
	glyphcache_current_memsize = glyphcache_current_memsize + size
	return true
end
function getGlyph(face, charcode)
	local hash = glyphCacheHash(face.hash, charcode)
	if glyphcache[hash] == nil then
		local glyph = face.ftface:renderGlyph(charcode)
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

function sizeUtf8Text(x, width, face, facehash, text, kerning)
	if text == nil then
		print("# sizeUtf8Text called without text");
		return
	end
	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local pen_y_top = 0
	local pen_y_bottom = 0
	local prevcharcode = 0
	--print("----------------- text:"..text)
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < (width - x) then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, facehash, charcode)
			if kerning and prevcharcode then
				local kern = face:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
				print("prev:"..string.char(prevcharcode).." curr:"..string.char(charcode).." kern:"..kern)
			else
				print("curr:"..string.char(charcode))
			end
			pen_x = pen_x + glyph.ax
			pen_y_top = math.max(pen_y_top, glyph.t)
			pen_y_bottom = math.max(pen_y_bottom, glyph.bb:getHeight() - glyph.t)
			--print("ax:"..glyph.ax.." t:"..glyph.t.." r:"..glyph.r.." h:"..glyph.bb:getHeight().." w:"..glyph.bb:getWidth().." yt:"..pen_y_top.." yb:"..pen_y_bottom)
			prevcharcode = charcode
		end
	end
	return { x = pen_x, y_top = pen_y_top, y_bottom = pen_y_bottom}
end

function renderUtf8Text(buffer, x, y, face, facehash, text, kerning, backgroundColor)
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
			local glyph = getGlyph(face, charcode)
			if kerning and prevcharcode then
				local kern = face.ftface:getKerning(prevcharcode, charcode)
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
