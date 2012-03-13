
blitbuffer.paintBorder = function (bb, x, y, w, h, bw, c)
	bb:paintRect(x, y, w, bw, c)
	bb:paintRect(x, y+h-bw, w, bw, c)
	bb:paintRect(x, y+bw, bw, h - 2*bw, c)
	bb:paintRect(x+w-bw, y+bw, bw, h - 2*bw, c)
end

--[[
Draw a progress bar according to following args:

@x:  start position in x axis
@y:  start position in y axis
@w:  width for progress bar
@h:  height for progress bar
@load_m_w: width margin for loading bar
@load_m_h: height margin for loading bar
@load_percent: progress in percent
@c:  color for loading bar
--]]
blitbuffer.progressBar = function (bb, x, y, w, h, 
									load_m_w, load_m_h, load_percent, c)
	if load_m_h*2 > h then
		load_m_h = h/2
	end
	blitbuffer.paintBorder(fb.bb, x, y, w, h, 2, 15)
	fb.bb:paintRect(x+load_m_w, y+load_m_h, 
					(w-2*load_m_w)*load_percent, (h-2*load_m_h), c)
end
