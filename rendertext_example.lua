#!./kpdfview
require "rendertext"
require "graphics"

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

print("open")
size = 50
--face = freetype.newBuiltinFace("sans", 64)
face = freetype.newFace("/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf", size)
print("got face")

if face:hasKerning() then
	print("has kerning")
end

width, height = fb:getSize()
fb.bb:paintRect(5,5,width-5,height-5,4);

faceHeight, faceAscender = face:getHeightAndAscender();
print("face height:"..tostring(faceHeight).." - ascender:"..faceAscender)
faceHeight = math.ceil(faceHeight)
faceAscender = math.ceil(faceAscender)
print("face height:"..tostring(faceHeight).." - ascender:"..faceAscender)

posY = 5 + faceAscender
renderUtf8Text(fb.bb, 5, posY, face, "h", "AV T.T: gxyt!", true)
posY = posY + faceHeight
renderUtf8Text(fb.bb, 5, posY, face, "h2", "AV T.T: gxyt!", false)

fb:refresh()

while true do
	local ev = input.waitForEvent()
end
