require "rendertext"

fb = einkfb.open("/dev/fb0")
width, height = fb:getSize()

print("open")

face = freetype.newBuiltinFace("Helvetica", 64)
print("got face")

renderUtf8Text(100,100,face,"h","Hello World! äöü")

fb:refresh()

while true do
	local ev = input.waitForEvent()
end
