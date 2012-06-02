glyphcache_max_memsize = 256*1024 -- 256kB glyphcache
glyphcache_current_memsize = 0
glyphcache = {}
glyphcache_max_age = 4
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
				break -- leave loop and check again if we have enough free space now
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
			glyph = glyph
		}
	else
		glyphcache[hash].age = glyphcache_max_age
	end
	return glyphcache[hash].glyph
end
function glyphCacheHash(face, charcode)
	return face..'_'..charcode;
end
function clearGlyphCache()
	glyphcache = {}
	glyphcache_current_memsize = 0
end

function sizeUtf8Text(x, width, face, text, kerning)
	if text == nil then
		debug("sizeUtf8Text called without text");
		return
	end
	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local pen_y_top = 0
	local pen_y_bottom = 0
	local prevcharcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < (width - x) then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, charcode)
			if kerning and prevcharcode then
				local kern = face.ftface:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
				--debug("prev:"..string.char(prevcharcode).." curr:"..string.char(charcode).." kern:"..kern)
			else
				--debug("curr:"..string.char(charcode))
			end
			pen_x = pen_x + glyph.ax
			pen_y_top = math.max(pen_y_top, glyph.t)
			pen_y_bottom = math.max(pen_y_bottom, glyph.bb:getHeight() - glyph.t)
			--debug("ax:"..glyph.ax.." t:"..glyph.t.." r:"..glyph.r.." h:"..glyph.bb:getHeight().." w:"..glyph.bb:getWidth().." yt:"..pen_y_top.." yb:"..pen_y_bottom)
			prevcharcode = charcode
		end
	end
	return { x = pen_x, y_top = pen_y_top, y_bottom = pen_y_bottom}
end

function renderUtf8Text(buffer, x, y, face, text, kerning)
	if text == nil then
		debug("renderUtf8Text called without text");
		return 0
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
				--debug("prev:"..string.char(prevcharcode).." curr:"..string.char(charcode).." pen_x:"..pen_x.." kern:"..kern)
				buffer:addblitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			else
				--debug(" curr:"..string.char(charcode))
				buffer:blitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			end
			pen_x = pen_x + glyph.ax
			prevcharcode = charcode
		end
	end
	return pen_x
end


-- NuPogodi: Some New Functions to render UTF8 text restricted by some width 'w'

function renderUtf8TextWidth(buffer, x, y, face, text, kerning, w)
	if text == nil then
		debug("renderUtf8Text called without text");
		return nil
	end
	local pen_x = 0
	local rest = ""
	local prevcharcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < w then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, charcode)
			if kerning and prevcharcode then
				local kern = face.ftface:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
				--debug("prev:"..string.char(prevcharcode).." curr:"..string.char(charcode).." pen_x:"..pen_x.." kern:"..kern)
				buffer:addblitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			else
				--debug(" curr:"..string.char(charcode))
				buffer:blitFrom(glyph.bb, x + pen_x + glyph.l, y - glyph.t, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight())
			end
			pen_x = pen_x + glyph.ax
			prevcharcode = charcode
		else
			-- accumulating the rest of text here
			rest = rest .. uchar
		end
	end
	return { leaved = rest, x = pen_x, y = y }
end

function SplitString(text)
	local words = {}
	local word = ""
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if uchar == "/" or uchar == " " or uchar == "-" or uchar == "_" or uchar == "\." then
			words[#words+1] = word .. uchar
			word = ""
		else
			word = word .. uchar
		end
	end
	-- add the rest of string as the last word
	words[#words+1] = word
	return words
end

function renderUtf8Multiline(buffer, x, y, face, text, kerning, w, line_spacing)
	-- at first, split a text on separate words
	local words = SplitString(text)
	
	-- test whether it is inside of reasonable values 1.0 < line_spacing < 5.0 or given in pixels (>5)
	-- default value is 1.75 ; getGlyph(face, 48).t = height of char '0'
	if line_spacing<1 then line_spacing=math.ceil(getGlyph(face, 48).t) -- single = minimum
		elseif line_spacing < 5 then line_spacing=math.ceil(getGlyph(face, 48).t * line_spacing)
		-- if line_spacing>5 then it seems to be defined in pixels
		elseif line_spacing>=5 then line_spacing=line_spacing 
		-- and, finally, default value
		else line_spacing = math.ceil(getGlyph(face, 48).t * 1.75) 
	end
	
	local lx = x
	for i = 1, #words do
		if sizeUtf8Text(lx, buffer:getWidth(), face, words[i], kerning).x < (w - lx + x) then
			lx = lx + renderUtf8TextWidth(buffer, lx, y, face, words[i], kerning, w - lx + x).x
		else
			-- set lx to the line start
			lx = x
			-- add the y-distance between lines
			y = y + line_spacing
			-- and draw next word
			lx = lx + renderUtf8TextWidth(buffer, lx, y, face, words[i], kerning, w - lx + x).x
		end -- if
	end --for 
	return { x = x, y = y }
end

