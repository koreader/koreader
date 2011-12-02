require "rendertext"

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

print("open")

face = freetype.newBuiltinFace("sans", 64)
--face = freetype.newFace("test.ttf", 64)
print("got face")

if face:hasKerning() then
	print("has kerning")
end

renderUtf8Text(fb.bb, 100, 100, face, "h", "AV T.T: gxyt!", true)
renderUtf8Text(fb.bb, 100, 200, face, "h", "AV T.T: gxyt!", false)

fb:refresh()

while true do
	local ev = input.waitForEvent()
end
