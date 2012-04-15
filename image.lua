Image = {}

function Image._getFileData(filename)
	local f = io.open(filename)
	local data = f:read("*a")
	f:close()
	return data
end

function Image.fromPNG(filename)
	local img = mupdfimg.new()
	img:loadPNGData(Image._getFileData(filename))
	local bb = img:toBlitBuffer()
	img:free()
	return bb
end

function Image.fromJPEG(filename)
	local img = mupdfimg.new()
	img:loadJPEGData(Image._getFileData(filename)(fimgdatailename))
	local bb = img:toBlitBuffer()
	img:free()
	return bb
end

