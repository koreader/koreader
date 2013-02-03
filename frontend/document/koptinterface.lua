require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/device"
require "ui/reader/readerconfig"

KoptOptions = {
	prefix = 'kopt',
	default_options = {
		{
			widget = "ProgressWidget",
			widget_align_center = 0.8,
			width = Screen:getWidth()*0.7,
			height = 5,
			percentage = 0.0,
			item_text = {"Goto"},
			item_align_center = 0.2,
			item_font_face = "tfont",
			item_font_size = 20,
		}
	},
	{
		icon = "resources/icons/appbar.transform.rotate.right.large.png",
		options = {
			{
				name = "screen_mode",
				name_text = "Screen Mode",
				toggle = {"portrait", "landscape"},
				args = {"portrait", "landscape"},
				default_arg = Screen:getScreenMode(),
				event = "SetScreenMode",
			}
		}
	},
	{
		icon = "resources/icons/appbar.crop.large.png",
		options = {
			{
				name = "trim_page",
				name_text = "Page Crop",
				toggle = {"auto", "manual"},
				values = {1, 0},
				default_value = 1,
			}
		}
	},
	{
		icon = "resources/icons/appbar.column.two.large.png",
		options = {
			{
				name = "page_margin",
				name_text = "Page Margin",
				toggle = {"small", "medium", "large"},
				values = {0.02, 0.06, 0.10},
				default_value = 0.06,
			},
			{
				name = "line_spacing",
				name_text = "Line Spacing",
				toggle = {"small", "medium", "large"},
				values = {1.0, 1.2, 1.4},
				default_value = 1.2,
			},
			{
				name = "max_columns",
				name_text = "Columns",
				item_text = {"1","2","3","4"},
				values = {1,2,3,4},
				default_value = 2,
			},
			{
				name = "justification",
				name_text = "Justification",
				item_text = {"auto","left","center","right","full"},
				values = {-1,0,1,2,3},
				default_value = -1,
			},
		}
	},
	{
		icon = "resources/icons/appbar.text.size.large.png",
		options = {
			{
				name = "font_size",
				item_text = {"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
				item_align_center = 1.0,
				spacing = Screen:getWidth()*0.03,
				item_font_size = {20,24,28,32,36,38,40,42,46,50},
				values = {0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.2, 2.8},
				default_value = 1.0,
			},
		}
	},
	{
		icon = "resources/icons/appbar.grade.b.large.png",
		options = {
			{
				name = "contrast",
				name_text = "Contrast",
				name_align_right = 0.2,
				item_text = {"lightest", "lighter", "default", "darker", "darkest"},
				item_font_size = math.floor(18*Screen:getWidth()/600),
				item_align_center = 0.8,
				values = {2.0, 1.5, 1.0, 0.5, 0.2},
				default_value = 1.0,
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "text_wrap",
				name_text = "Reflow",
				toggle = {"On", "Off"},
				values = {1, 0},
				default_value = 0,
				event = "RedrawCurrentPage",
			},
			{
				name="screen_rotation",
				name_text = "Vertical Text",
				toggle = {"Off", "On"},
				values = {0, 90},
				default_value = 0,
			},
			{
				name = "word_spacing",
				name_text = "Word Gap",
				toggle = {"small", "medium", "large"},
				values = {0.05, 0.15, 0.375},
				default_value = 0.15,
			},
			{
				name = "defect_size",
				name_text = "Defect Size",
				toggle = {"small", "medium", "large"},
				values = {0.5, 1.0, 2.0},
				default_value = 1.0,
			},
			{
				name = "quality",
				name_text = "Render Quality",
				toggle = {"low", "default", "high"},
				values={0.5, 0.8, 1.0},
				default_value = 0.8,
			},
			{
				name = "auto_straighten",
				name_text = "Auto Straighten",
				toggle = {"0 deg", "5 deg", "10 deg"},
				values = {0, 5, 10},
				default_value = 0,
			},
			{
				name = "detect_indent",
				name_text = "Indentation",
				toggle = {"On", "Off"},
				values = {1, 0},
				default_value = 1,
				show = false,
			},
		}
	},
}

KoptInterface = {}

-- get reflow context
function KoptInterface:getKOPTContext(doc, pageno)
	local kc = KOPTContext.new()
	kc:setTrim(doc.configurable.trim_page)
	kc:setWrap(doc.configurable.text_wrap)
	kc:setIndent(doc.configurable.detect_indent)
	kc:setRotate(doc.configurable.screen_rotation)
	kc:setColumns(doc.configurable.max_columns)
	kc:setDeviceDim(doc.screen_size.w, doc.screen_size.h)
	kc:setDeviceDPI(doc.screen_dpi)
	kc:setStraighten(doc.configurable.auto_straighten)
	kc:setJustification(doc.configurable.justification)
	kc:setZoom(doc.configurable.font_size)
	kc:setMargin(doc.configurable.page_margin)
	kc:setQuality(doc.configurable.quality)
	kc:setContrast(doc.configurable.contrast)
	kc:setDefectSize(doc.configurable.defect_size)
	kc:setLineSpacing(doc.configurable.line_spacing)
	kc:setWordSpacing(doc.configurable.word_spacing)
	local bbox = doc:getUsedBBox(pageno)
	kc:setBBox(bbox.x0, bbox.y0, bbox.x1, bbox.y1)
	return kc
end

-- calculates page dimensions
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
	-- check cached page size
	local hash = "kctx|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
	local cached = Cache:check(hash)
	if not cached then
		local kc = self:getKOPTContext(doc, pageno)
		local page = doc._document:openPage(pageno)
		-- reflow page
		page:reflow(kc, 0)
		page:close()
		local fullwidth, fullheight = kc:getPageDim()
		DEBUG("page::reflowPage:", "fullwidth:", fullwidth, "fullheight:", fullheight)
		local page_size = Geom:new{ w = fullwidth, h = fullheight }
		-- cache reflowed page size and kc
		Cache:insert(hash, CacheItem:new{ kctx = kc })
		return page_size
	end
	--DEBUG("Found cached koptcontex on page", pageno, cached)
	local fullwidth, fullheight = cached.kctx:getPageDim()
	local page_size = Geom:new{ w = fullwidth, h = fullheight }
	return page_size
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	doc.render_mode = render_mode
	local hash = "renderpg|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
	local page_size = self:getPageDimensions(doc, pageno, zoom, rotation)
	-- this will be the size we actually render
	local size = page_size
	-- we prefer to render the full page, if it fits into cache
	if not Cache:willAccept(size.w * size.h / 2) then
		-- whole page won't fit into cache
		DEBUG("rendering only part of the page")
		-- TODO: figure out how to better segment the page
		if not rect then
			DEBUG("aborting, since we do not have a specification for that part")
			-- required part not given, so abort
			return
		end
		-- only render required part
		hash = "renderpg|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|').."|"..tostring(rect)
		size = rect
	end
	
	local cached = Cache:check(hash)
	if cached then return cached end

	-- prepare cache item with contained blitbuffer	
	local tile = CacheItem:new{
		size = size.w * size.h / 2 + 64, -- estimation
		excerpt = size,
		pageno = pageno,
		bb = Blitbuffer.new(size.w, size.h)
	}

	-- draw to blitbuffer
	local kc_hash = "kctx|"..doc.file.."|"..pageno.."|"..doc.configurable:hash('|')
	local page = doc._document:openPage(pageno)
	local cached = Cache:check(kc_hash)
	if cached then
		page:rfdraw(cached.kctx, tile.bb)
		page:close()
		DEBUG("cached hash", hash)
		if not Cache:check(hash) then
			Cache:insert(hash, tile)
		end
		return tile
	end
	DEBUG("Error: cannot render page before reflowing.")
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
	local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
	DEBUG("now painting", tile, rect)
	target:blitFrom(tile.bb,
		x, y, 
		rect.x - tile.excerpt.x,
		rect.y - tile.excerpt.y,
		rect.w, rect.h)
end
