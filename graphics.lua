
blitbuffer.paintBorder = function (bb, x, y, w, h, bw, c)
	bb:paintRect(x, y, w, bw, c)
	bb:paintRect(x, y+h-bw, w, bw, c)
	bb:paintRect(x, y+bw, bw, h - 2*bw, c)
	bb:paintRect(x+w-bw, y+bw, bw, h - 2*bw, c)
end
