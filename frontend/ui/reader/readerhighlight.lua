require "ui/widget/buttontable"

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
		HoldRelease = {
			GestureRange:new{
				ges = "hold_release",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight()
				}
			}
		},
		HoldPan = {
			GestureRange:new{
				ges = "hold_pan",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight()
				},
				rate = 2.0,
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
	local function inside_box(ges, box)
		local pos = self.view:screenToPageTransform(ges.pos)
		local x, y = pos.x, pos.y
		if box.x <= x and box.y <= y 
			and box.x + box.w >= x 
			and box.y + box.h >= y then
			return true
		end
		return false
	end
	if self.hold_pos then
		self.view.highlight.temp[self.hold_pos.page] = nil
		UIManager:setDirty(self.dialog, "partial")
		self.hold_pos = nil
		return true
	end
	local pages = self.view:getCurrentPageList()
	for key, page in pairs(pages) do
		local items = self.view.highlight.saved[page]
		if not items then items = {} end
		for i = 1, #items do
			for j = 1, #items[i].boxes do
				if inside_box(ges, items[i].boxes[j]) then
					DEBUG("Tap on hightlight")
					self.edit_highlight_dialog = ButtonTable:new{
						buttons = {
							{
								{
									text = _("Delete"),
									callback = function() self:deleteHighlight(page, i) end,
								},
								{
									text = _("Edit"),
									enabled = false,
									callback = function() self:editHighlight() end,
								},
							},
						},
						tap_close_callback = function() self.ui:handleEvent(Event:new("Tap")) end,
					}
					UIManager:show(self.edit_highlight_dialog)
					return true
				end
			end
		end
	end
end

function ReaderHighlight:onHold(arg, ges)
	self.hold_pos = self.view:screenToPageTransform(ges.pos)
	DEBUG("hold position in page", self.hold_pos)
	if not self.hold_pos then
		DEBUG("not inside page area")
		return true
	end
	self.page_boxes = self.ui.document:getTextBoxes(self.hold_pos.page)
	--DEBUG("page text", page_boxes)
	
	if not self.page_boxes or #self.page_boxes == 0 then
		DEBUG("no page boxes detected")
		return true
	end
	
	self.selected_word = self:getWordFromPosition(self.page_boxes, self.hold_pos)
	DEBUG("selected word:", self.selected_word)
	if self.selected_word then
		local boxes = {}
		table.insert(boxes, self.selected_word.box)
		self.view.highlight.temp[self.hold_pos.page] = boxes
		UIManager:setDirty(self.dialog, "partial")
	end
	return true
end

function ReaderHighlight:onHoldPan(arg, ges)
	if not self.page_boxes or #self.page_boxes == 0 then
		DEBUG("no page boxes detected")
		return true
	end
	self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
	DEBUG("holdpan position in page", self.holdpan_pos)
	self.selected_text = self:getTextFromPositions(self.page_boxes, self.hold_pos, self.holdpan_pos)
	--DEBUG("selected text:", self.selected_text)
	if self.selected_text then
		self.view.highlight.temp[self.hold_pos.page] = self.selected_text.boxes
		-- remove selected word if hold moves out of word box
		if self.selected_word and
			not self.selected_word.box:contains(self.selected_text.boxes[1]) then
			self.selected_word = nil
		end
		UIManager:setDirty(self.dialog, "partial")
	end
end

function ReaderHighlight:onHoldRelease(arg, ges)
	if self.selected_word then
		-- if we extracted text directly
		if self.selected_word.word then
			self.ui:handleEvent(Event:new("LookupWord", self.selected_word.word))
		-- or we will do OCR
		else
			local word_box = self.selected_word.box
			word_box.x = word_box.x - math.floor(word_box.h * 0.1)
			word_box.y = word_box.y - math.floor(word_box.h * 0.2)
			word_box.w = word_box.w + math.floor(word_box.h * 0.2)
			word_box.h = word_box.h + math.floor(word_box.h * 0.4)
			local word = self.ui.document:getOCRWord(self.hold_pos.page, word_box)
			DEBUG("OCRed word:", word)
			self.ui:handleEvent(Event:new("LookupWord", word))
		end
		self.selected_word = nil
	elseif self.selected_text then
		DEBUG("show highlight dialog")
		self.highlight_dialog = ButtonTable:new{
			buttons = {
				{
					{
						text = _("Highlight"),
						callback = function() self:saveHighlight() end,
					},
					{
						text = _("Add Note"),
						enabled = false,
						callback = function() self:addNote() end,
					},
				},
				{
					{
						text = _("Share"),
						enabled = false,
						callback = function() self:shareHighlight() end,
					},
					{
						text = _("More"),
						enabled = false,
						callback = function() self:moreAction() end,
					},
				},
			},
			tap_close_callback = function() self.ui:handleEvent(Event:new("Tap")) end,
		}
		UIManager:show(self.highlight_dialog)
	end
	return true
end

function ReaderHighlight:saveHighlight()
	DEBUG("save highlight")
	UIManager:close(self.highlight_dialog)
	local page = self.hold_pos.page
	if self.hold_pos and self.selected_text then
		if not self.view.highlight.saved[page] then
			self.view.highlight.saved[page] = {}
		end
		local hl_item = {}
		hl_item["text"] = self.selected_text.text
		hl_item["boxes"] = self.selected_text.boxes
		hl_item["datetime"] = os.date("%Y-%m-%d %H:%M:%S"),
		table.insert(self.view.highlight.saved[page], hl_item)
		if self.selected_text.text ~= "" then
			self:exportToClippings(page, hl_item)
		end
	end
	--DEBUG("saved hightlights", self.view.highlight.saved[page])
end

function ReaderHighlight:exportToClippings(page, item)
	DEBUG("export highlight to My Clippings")
	local clippings = io.open("/mnt/us/documents/My Clippings.txt", "a+")
	if clippings then
		local current_locale = os.setlocale()
		os.setlocale("C")
		clippings:write(self.document.file:gsub("(.*/)(.*)", "%2").."\n")
		clippings:write("- Koreader Highlight Page "..page.." ")
		clippings:write("| Added on "..os.date("%A, %b %d, %Y %I:%M:%S %p\n\n"))
		clippings:write(item["text"].."\n")
		clippings:write("==========\n")
		clippings:close()
		os.setlocale(current_locale)
	end
end

function ReaderHighlight:addNote()
	DEBUG("add Note")
	UIManager:close(self.highlight_dialog)
end

function ReaderHighlight:shareHighlight()
	DEBUG("share highlight")
	UIManager:close(self.highlight_dialog)
end

function ReaderHighlight:moreAction()
	DEBUG("more action")
	UIManager:close(self.highlight_dialog)
end

function ReaderHighlight:deleteHighlight(page, i)
	DEBUG("delete highlight")
	UIManager:close(self.edit_highlight_dialog)
	table.remove(self.view.highlight.saved[page], i)
end

function ReaderHighlight:editHighlight()
	DEBUG("edit highlight")
	UIManager:close(self.edit_highlight_dialog)
end

--[[
get index of nearest word box around pos
--]]
local function getWordBoxIndices(boxes, pos)
	local function inside_box(box)
		local x, y = pos.x, pos.y
		if box.x0 <= x and box.y0 <= y and box.x1 >= x and box.y1 >= y then
			return true
		end
		return false
	end
	local function box_distance(i, j)
		local wb = boxes[i][j]
		if inside_box(wb) then
			return 0
		else
			local x0, y0 = pos.x, pos.y
			local x1, y1 = (wb.x0 + wb.x1) / 2, (wb.y0 + wb.y1) / 2
			return (x0 - x1)*(x0 - x1) + (y0 - y1)*(y0 - y1)
		end
	end

	local m, n = 1, 1
	for i = 1, #boxes do
		for j = 1, #boxes[i] do
			if box_distance(i, j) < box_distance(m, n) then
				m, n = i, j
			end
		end
	end
	return m, n
end

--[[
get word and word box around pos
--]]
function ReaderHighlight:getWordFromPosition(boxes, pos)
	local i, j = getWordBoxIndices(boxes, pos)
	local lb = boxes[i]
	local wb = boxes[i][j]
	if lb and wb then
		local box = Geom:new{
			x = wb.x0, y = lb.y0, 
			w = wb.x1 - wb.x0,
			h = lb.y1 - lb.y0,
		}
		return {
			word = wb.word,
			box = box,
		}
	end
end

--[[
get text and text boxes between pos0 and pos1
--]]
function ReaderHighlight:getTextFromPositions(boxes, pos0, pos1)
    local line_text = ""
    local line_boxes = {}
    local i_start, j_start = getWordBoxIndices(boxes, pos0)
    local i_stop, j_stop = getWordBoxIndices(boxes, pos1)
    if i_start == i_stop and j_start > j_stop or i_start > i_stop then
    	i_start, i_stop = i_stop, i_start
    	j_start, j_stop = j_stop, j_start
    end
    for i = i_start, i_stop do
    	-- insert line words
    	local j0 = i > i_start and 1 or j_start
    	local j1 = i < i_stop and #boxes[i] or j_stop
    	for j = j0, j1 do
    		local word = boxes[i][j].word
    		if word then
    			-- if last character of this word is an ascii char then append a space
    			local space = (word:match("[%z\194-\244][\128-\191]*$") or j == j1)
    						   and "" or " "
    			line_text = line_text..word..space
    		end
    	end
    	-- insert line box
    	local lb = boxes[i]
    	if i > i_start and i < i_stop then
    		local line_box = Geom:new{
				x = lb.x0, y = lb.y0, 
				w = lb.x1 - lb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i == i_start and i < i_stop then
    		local wb = boxes[i][j_start]
    		local line_box = Geom:new{
				x = wb.x0, y = lb.y0, 
				w = lb.x1 - wb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i > i_start and i == i_stop then
    		local wb = boxes[i][j_stop]
    		local line_box = Geom:new{
				x = lb.x0, y = lb.y0, 
				w = wb.x1 - lb.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	elseif i == i_start and i == i_stop then
    		local wb_start = boxes[i][j_start]
    		local wb_stop = boxes[i][j_stop]
    		local line_box = Geom:new{
				x = wb_start.x0, y = lb.y0, 
				w = wb_stop.x1 - wb_start.x0,
				h = lb.y1 - lb.y0,
			}
    		table.insert(line_boxes, line_box)
    	end
    end
    return {
    	text = line_text,
    	boxes = line_boxes,
    }
end
