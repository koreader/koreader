
ReaderHighlight = InputContainer:new{}

function ReaderHighlight:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ShowToc = {
				{ "." },
				doc = _("highlight text") },
		}
	end
end

function ReaderHighlight:initGesListener()
	self.ges_events = {
		Tap = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight()
				}
			}
		},
		Hold = {
			GestureRange:new{
				ges = "hold",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight()
				}
			}
		},
	}
end

function ReaderHighlight:onSetDimensions(dimen)
	-- update listening according to new screen dimen
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderHighlight:onTap(arg, ges)
	if self.view.highlight.rect then
		self.view.highlight.rect = nil
		UIManager:setDirty(self.dialog, "partial")
		return true
	end
end

function ReaderHighlight:onHold(arg, ges)
	self.pos = self.view:screenToPageTransform(ges.pos)
	DEBUG("hold position in page", self.pos)
	if not self.pos then
		DEBUG("not inside page area")
		return true
	end
	local text_boxes = self.ui.document:getTextBoxes(self.pos.page)
	--DEBUG("page text", text_boxes)
	
	if not text_boxes or #text_boxes == 0 then
		DEBUG("no text box detected")
		return true
	end
	
	self.word_info = self:getWordFromBoxes(text_boxes, self.pos)
	DEBUG("hold word info in page", self.word_info)
	if self.word_info then
		-- if we extracted text directly
		if self.word_info.word then
			self.ui:handleEvent(Event:new("LookupWord", self.word_info.word))
		-- or we will do OCR
		else
			UIManager:scheduleIn(0.1, function()
				local word_box = self.word_info.box
				word_box.x = word_box.x - math.floor(word_box.h * 0.2)
				word_box.y = word_box.y - math.floor(word_box.h * 0.4)
				word_box.w = word_box.w + math.floor(word_box.h * 0.4)
				word_box.h = word_box.h + math.floor(word_box.h * 0.6)
				local word = self.ui.document:getOCRWord(self.pos.page, word_box)
				DEBUG("OCRed word:", word)
				self.ui:handleEvent(Event:new("LookupWord", word))
			end)
		end
		
		local screen_rect = self.view:pageToScreenTransform(self.pos.page, self.word_info.box)
		DEBUG("highlight word rect", screen_rect)
		if screen_rect then
			screen_rect.x = screen_rect.x - screen_rect.h * 0.2
			screen_rect.y = screen_rect.y - screen_rect.h * 0.2
			screen_rect.w = screen_rect.w + screen_rect.h * 0.4
			screen_rect.h = screen_rect.h + screen_rect.h * 0.4
			self.view.highlight.rect = screen_rect
			UIManager:setDirty(self.dialog, "partial")
		end
	end
	return true
end

function ReaderHighlight:getWordFromBoxes(boxes, pos)
	local function ges_inside(x0, y0, x1, y1)
		local x, y = pos.x, pos.y
		if x0 ~= nil and y0 ~= nil and x1 ~= nil and y1 ~= nil then
			if x0 <= x and y0 <= y and x1 >= x and y1 >= y then
				return true
			end
		end
		return false
	end
	
	for i = 1, #boxes do
		local l = boxes[i]
		if ges_inside(l.x0, l.y0, l.x1, l.y1) then
			--DEBUG("line box", l.x0, l.y0, l.x1, l.y1)
			for j = 1, #boxes[i] do
				local w = boxes[i][j]
				if ges_inside(w.x0, w.y0, w.x1, w.y1) then
					local box = Geom:new{
						x = w.x0, y = w.y0, 
						w = w.x1 - w.x0,
						h = w.y1 - w.y0,
					}
					return {
						word = w.word,
						box = box,
					}
				end -- end if inside word box
			end -- end for each word
		end -- end if inside line box
	end -- end for each line
end
