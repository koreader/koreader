--[[
a cache for rendered tiles
]]--
cache_max_memsize = 1024*1024*5 -- 5MB tile cache
cache_current_memsize = 0
cache = {}
cache_max_age = 20
function cacheclaim(size)
	if(size > cache_max_memsize) then
		error("too much memory claimed")
		return false
	end
	repeat
		for k, _ in pairs(cache) do
			if cache[k].age > 0 then
				print("aging slot="..k)
				cache[k].age = cache[k].age - 1
			else
				cache_current_memsize = cache_current_memsize - cache[k].size
				cache[k] = nil
			end
		end
	until cache_current_memsize + size <= cache_max_memsize
	cache_current_memsize = cache_current_memsize + size
	print("cleaned cache to fit new tile (size="..size..")")
	return true
end
function draworcache(no, zoom, offset_x, offset_y, width, height, gamma)
	local hash = cachehash(no, zoom, offset_x, offset_y, width, height, gamma)
	if cache[hash] == nil then
		cacheclaim(width * height / 2);
		cache[hash] = {
			age = cache_max_age,
			size = width * height / 2,
			bb = blitbuffer.new(width, height)
		}
		print("drawing page="..no.." to slot="..hash)
		local page = doc:openPage(no)
		local dc = setzoom(page, hash)
		page:draw(dc, cache[hash].bb, 0, 0)
		page:close()
	end
	return hash
end
function cachehash(no, zoom, offset_x, offset_y, width, height, gamma)
	return no..'_'..zoom..'_'..offset_x..','..offset_y..'-'..width..'x'..height..'_'..gamma;
end
function clearcache()
	cache = {}
end
