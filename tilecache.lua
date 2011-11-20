--[[
a cache for rendered tiles
]]--

function init_tilecache()
	cache = {
		{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil },
		{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil },
		{ age = 0, no = 0, bb = blitbuffer.new(width, height), dc = pdf.newDC(), page = nil }
	}
end
function freecache()
	for i = 1, #cache do
		if cache[i].page ~= nil then
			print("freeing slot="..i.." oldpage="..cache[i].no)
			cache[i].page:close()
			cache[i].page = nil
		end
	end
end
function checkcache(no)
	for i = 1, #cache do
		if cache[i].no == no and cache[i].page ~= nil then
			print("cache hit: slot="..i.." page="..no)
			return i
		end
	end
	print("cache miss")
	return nil
end
function cacheslot()
	freeslot = nil
	while freeslot == nil do
		for i = 1, #cache do
			if cache[i].age > 0 then
				print("aging slot="..i)
				cache[i].age = cache[i].age - 1
			else
				if cache[i].page ~= nil then
					print("freeing slot="..i.." oldpage="..cache[i].no)
					cache[i].page:close()
					cache[i].page = nil
				end
				freeslot = i
			end
		end
	end
	print("returning free slot="..freeslot)
	return freeslot
end

function draworcache(no)
	local slot = checkcache(no)
	if slot == nil then
		slot = cacheslot()
		cache[slot].no = no
		cache[slot].age = #cache
		cache[slot].page = doc:openPage(no)
		setzoom(slot)
		print("drawing page="..no.." to slot="..slot)
		cache[slot].page:draw(cache[slot].dc, cache[slot].bb, 0, 0)
	end
	return slot
end
