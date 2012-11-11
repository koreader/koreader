-- framebuffer update policy state:
DRCOUNT = 5
-- default to full refresh on every page turn
DRCOUNTMAX = 0

-- zoom state:
DGLOBALZOOM = 1.0
DGLOBALZOOM_ORIG = 1.0
DGLOBALZOOM_MODE = -1 -- ZOOM_FIT_TO_PAGE

DGLOBALROTATE = 0

-- gamma setting:
DGLOBALGAMMA = 1.0   -- GAMMA_NO_GAMMA

-- DjVu page rendering mode (used in djvu.c:drawPage())
-- See comments in djvureader.lua:DJVUReader:select_render_mode()
DRENDER_MODE = 0 -- COLOUR

-- set panning distance
DSHIFT_X = 100
DSHIFT_Y = 50
-- step to change zoom manually, default = 16%
DSTEP_MANUAL_ZOOM = 16
DPAN_BY_PAGE = false -- using shift_[xy] or width/height
DPAN_MARGIN = 5 -- horizontal margin for two-column zoom (in pixels)
DPAN_OVERLAP_VERTICAL = 30

-- tile cache configuration:
DCACHE_MAX_MEMSIZE = 1024*1024*5 -- 5MB tile cache
DCACHE_MAX_TTL = 20 -- time to live

-- renderer cache size
DCACHE_DOCUMENT_SIZE = 1024*1024*8 -- FIXME random, needs testing

-- default value for battery level logging
DBATTERY_LOGGING = false

-- background colour: 8 = gray, 0 = white, 15 = black
DBACKGROUND_COLOR = 8

-- timeout for info messages in ms
DINFO_TIMEOUT_FAST=0
DINFO_TIMEOUT_SLOW=1500

-- toggle defaults
DUNIREADER_SHOW_OVERLAP_ENABLE = true
DUNIREADER_SHOW_LINKS_ENABLE = true
DUNIREADER_COMICS_MODE_ENABLE = true
DUNIREADER_RTL_MODE_ENABLE = false
DUNIREADER_PAGE_MODE_ENABLE = false

DDJVUREADER_SHOW_OVERLAP_ENABLE = true
DDJVUREADER_SHOW_LINKS_ENABLE = false
DDJVUREADER_COMICS_MODE_ENABLE = true
DDJVUREADER_RTL_MODE_ENABLE = false
DDJVUREADER_PAGE_MODE_ENABLE = false

DKOPTREADER_SHOW_OVERLAP_ENABLE = true
DKOPTREADER_SHOW_LINKS_ENABLE = false
DKOPTREADER_COMICS_MODE_ENABLE = false
DKOPTREADER_RTL_MODE_ENABLE = false
DKOPTREADER_PAGE_MODE_ENABLE = false

DPICVIEWER_SHOW_OVERLAP_ENABLE = false
DPICVIEWER_SHOW_LINKS_ENABLE = false
DPICVIEWER_COMICS_MODE_ENABLE = true
DPICVIEWER_RTL_MODE_ENABLE = false
DPICVIEWER_PAGE_MODE_ENABLE = false

