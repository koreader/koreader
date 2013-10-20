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
		if pos then
			local x, y = pos.x, pos.y
			if box.x <= x and box.y <= y 
				and box.x + box.w >= x 
				and box.y + box.h >= y then
				return true
			end
		end
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
			local pos0, pos1 = items[i].pos0, items[i].pos1
			local boxes = self.ui.document:getPageBoxesFromPositions(page, pos0, pos1)
			if boxes then
				for index, box in pairs(boxes) do
					if inside_box(ges, box) then
						DEBUG("Tap on hightlight")
						self.edit_highlight_dialog = HighlightDialog:new{
							buttons = {
								{
									{
										text = _("Delete"),
										callback = function()
											self:deleteHighlight(page, i)
											UIManager:close(self.edit_highlight_dialog)
										end,
									},
									{
										text = _("Edit"),
										enabled = false,
										callback = function()
											self:editHighlight()
											UIManager:close(self.edit_highlight_dialog)
										end,
									},
								},
							},
						}
						UIManager:show(self.edit_highlight_dialog)
						return true
					end
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

	self.selected_word = self.ui.document:getWordFromPosition(self.hold_pos)
	DEBUG("selected word:", self.selected_word)
	if self.selected_word then
		local boxes = {}
		table.insert(boxes, self.selected_word.sbox)
		self.view.highlight.temp[self.hold_pos.page] = boxes
		UIManager:setDirty(self.dialog, "partial")
	end
	return true
end

function ReaderHighlight:onHoldPan(arg, ges)
	if self.hold_pos == nil then
		DEBUG("no previous hold position")
		return true
	end
	self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
	DEBUG("holdpan position in page", self.holdpan_pos)
	self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.holdpan_pos)
	DEBUG("selected text:", self.selected_text)
	if self.selected_text then
		self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
		-- remove selected word if hold moves out of word box
		if self.selected_word and
			not self.selected_word.sbox:contains(self.selected_text.sboxes[1]) then
			self.selected_word = nil
		end
		UIManager:setDirty(self.dialog, "partial")
	end
end

function ReaderHighlight:lookup(selected_word)
	-- if we extracted text directly
	if selected_word.word then
		self.ui:handleEvent(Event:new("LookupWord", selected_word.word))
	-- or we will do OCR
	else
		local word = self.ui.document:getOCRWord(self.hold_pos.page, selected_word)
		DEBUG("OCRed word:", word)
		self.ui:handleEvent(Event:new("LookupWord", word))
	end
end

function ReaderHighlight:translate(selected_text)
	if selected_text.text ~= "" then
		self.ui:handleEvent(Event:new("TranslateText", selected_text.text))
	-- or we will do OCR
	else
		local text = self.ui.document:getOCRText(self.hold_pos.page, selected_text)
		DEBUG("OCRed text:", text)
		self.ui:handleEvent(Event:new("TranslateText", text))
	end
end

HighlightDialog = InputContainer:new{
	buttons = nil,
	tap_close_callback = nil,
}

function HighlightDialog:init()
	if Device:hasKeyboard() then
		key_events = {
			AnyKeyPressed = { { Input.group.Any },
				seqtext = "any key", doc = _("close dialog") }
		}
	else
		self.ges_events.TapClose = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				}
			}
		}
	end
	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			ButtonTable:new{
				width = Screen:getWidth()*0.9,
				buttons = self.buttons,
			},
			background = 0,
			bordersize = 2,
			radius = 7,
			padding = 2,
		}
	}
end

function HighlightDialog:onTapClose()
	UIManager:close(self)
	if self.tap_close_callback then
		self.tap_close_callback()
	end
	return true
end

function ReaderHighlight:onHoldRelease(arg, ges)
	if self.selected_word then
		self:lookup(self.selected_word)
		self.selected_word = nil
	elseif self.selected_text then
		DEBUG("show highlight dialog")
		self.highlight_dialog = HighlightDialog:new{
			buttons = {
				{
					{
						text = _("Highlight"),
						callback = function()
							self:saveHighlight()
							UIManager:close(self.highlight_dialog)
							self.ui:handleEvent(Event:new("Tap"))
						end,
					},
					{
						text = _("Add Note"),
						enabled = false,
						callback = function()
							self:addNote()
							UIManager:close(self.highlight_dialog)
							self.ui:handleEvent(Event:new("Tap"))
						end,
					},
				},
				{
					{
						text = _("Translate"),
						callback = function()
							self:translate(self.selected_text)
							UIManager:close(self.highlight_dialog)
							self.ui:handleEvent(Event:new("Tap"))
						end,
					},
					{
						text = _("Share"),
						enabled = false,
						callback = function()
							self:shareHighlight()
							UIManager:close(self.highlight_dialog)
							self.ui:handleEvent(Event:new("Tap"))
						end,
					},
				},
				{
					{
						text = _("More"),
						enabled = false,
						callback = function()
							self:moreAction()
							UIManager:close(self.highlight_dialog)
							self.ui:handleEvent(Event:new("Tap"))
						end,
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
	local page = self.hold_pos.page
	if self.hold_pos and self.selected_text then
		if not self.view.highlight.saved[page] then
			self.view.highlight.saved[page] = {}
		end
		local hl_item = {}
		hl_item["text"] = self.selected_text.text
		hl_item["pos0"] = self.selected_text.pos0
		hl_item["pos1"] = self.selected_text.pos1
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
	if clippings and item.text then
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
end

function ReaderHighlight:shareHighlight()
	DEBUG("share highlight")
end

function ReaderHighlight:moreAction()
	DEBUG("more action")
end

function ReaderHighlight:deleteHighlight(page, i)
	DEBUG("delete highlight")	
	table.remove(self.view.highlight.saved[page], i)
end

function ReaderHighlight:editHighlight()
	DEBUG("edit highlight")
end
