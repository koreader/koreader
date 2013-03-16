require "ui/widget/base"


--[[
Dummy Widget that reserves horizontal space
--]]
HorizontalSpan = Widget:new{
	width = 0,
}

function HorizontalSpan:getSize()
	return {w = self.width, h = 0}
end


--[[
Dummy Widget that reserves vertical space
--]]
VerticalSpan = Widget:new{
	width = 0,
}

function VerticalSpan:getSize()
	return {w = 0, h = self.width}
end


