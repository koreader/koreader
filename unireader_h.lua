require "keys"
require "settings"
require "selectmenu"
require "commands"
require "helppage"
require "dialog"

UniReader = {
	-- "constants":
	ZOOM_BY_VALUE = 0,
	ZOOM_FIT_TO_PAGE = -1,
	ZOOM_FIT_TO_PAGE_WIDTH = -2,
	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
	ZOOM_FIT_TO_CONTENT = -4,
	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,
	ZOOM_FIT_TO_CONTENT_WIDTH_PAN = -7,
	--ZOOM_FIT_TO_CONTENT_HEIGHT_PAN = -8,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN = -9,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH = -10,

	GAMMA_NO_GAMMA = 1.0,

	-- framebuffer update policy state:
	rcount = 5,
	-- default to full refresh on every page turn
	rcountmax = 0,

	-- zoom state:
	globalzoom = 1.0,
	globalzoom_orig = 1.0,
	globalzoom_mode = -1, -- ZOOM_FIT_TO_PAGE

	globalrotate = 0,

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- DjVu page rendering mode (used in djvu.c:drawPage())
	-- See comments in djvureader.lua:DJVUReader:select_render_mode()
	render_mode = 0, -- COLOUR

	-- cached tile size
	fullwidth = 0,
	fullheight = 0,
	-- size of current page for current zoom level in pixels
	cur_full_width = 0,
	cur_full_height = 0,
	cur_bbox = {}, -- current page bbox
	offset_x = 0,
	offset_y = 0,
	dest_x = 0, -- real offset_x when it's smaller than screen, so it's centered
	dest_y = 0,
	min_offset_x = 0,
	min_offset_y = 0,
	content_top = 0, -- for ZOOM_FIT_TO_CONTENT_WIDTH_PAN (prevView)

	-- set panning distance
	shift_x = 100,
	shift_y = 50,
	-- step to change zoom manually, default = 16%
	step_manual_zoom = 16,
	pan_by_page = false, -- using shift_[xy] or width/height
	pan_x = 0, -- top-left offset of page when pan activated
	pan_y = 0,
	pan_margin = 5, -- horizontal margin for two-column zoom (in pixels)
	pan_overlap_vertical = 30,
	show_overlap = 0,
	show_overlap_enable,
	show_links_enable,
	comics_mode_enable,
	rtl_mode_enable, -- rtl = right-to-left

	-- the document:
	doc = nil,
	-- the document's setting store:
	settings = nil,
	-- list of available commands:
	commands = nil,

	-- we will use this one often, so keep it "static":
	nulldc = DrawContext.new(),

	-- tile cache configuration:
	cache_max_memsize = 1024*1024*5, -- 5MB tile cache
	cache_max_ttl = 20, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},
	-- renderer cache size
	cache_document_size = 1024*1024*8, -- FIXME random, needs testing

	pagehash = nil,

	-- we use array to simluate two stacks,
	-- one for backwards, one for forwards
	jump_history = {cur = 1},
	bookmarks = {},
	highlight = {},
	toc = nil,
	toc_expandable = false, -- if true then TOC contains expandable/collapsible items
	toc_children = nil, -- each element is the list of children for each TOC node (nil if none)
	toc_xview = nil, -- fully expanded (and marked with '+') view of TOC
	toc_cview = nil, -- current view of TOC
	toc_curidx_to_x = nil, -- current view to expanded view map

	bbox = {}, -- override getUsedBBox

	last_search = {}
}

	-- DEFAULTS
	DUNIREADER_SHOW_OVERLAP_ENABLE = true
	DUNIREADER_SHOW_LINKS_ENABLE = true
	DUNIREADER_COMICS_MODE_ENABLE = false
	DUNIREADER_RTL_MODE_ENABLE = false
	
	DDJVUREADER_SHOW_OVERLAP_ENABLE = true
	DDJVUREADER_SHOW_LINKS_ENABLE = false
	DDJVUREADER_COMICS_MODE_ENABLE = false
	DDJVUREADER_RTL_MODE_ENABLE = false
	
	DKOPTREADER_SHOW_OVERLAP_ENABLE = true
	DKOPTREADER_SHOW_LINKS_ENABLE = false
	DKOPTREADER_COMICS_MODE_ENABLE = false
	DKOPTREADER_RTL_MODE_ENABLE = false
	
	DPICVIEWER_SHOW_OVERLAP_ENABLE = false
	DPICVIEWER_SHOW_LINKS_ENABLE = false
	DPICVIEWER_COMICS_MODE_ENABLE = false
	DPICVIEWER_RTL_MODE_ENABLE = false

