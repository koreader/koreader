-- number of page turns between full screen refresh
-- default to full refresh on every page turn
DRCOUNTMAX = 6

-- full screen mode, 1 for true, 0 for false
DFULL_SCREEN = 1

-- scroll mode, 1 for true, 0 for false
DSCROLL_MODE = 0

-- default gamma setting:
DGLOBALGAMMA = 1.0

-- DjVu page rendering mode (used in djvu.c:drawPage())
-- See comments in djvureader.lua:DJVUReader:select_render_mode()
DRENDER_MODE = 0 -- 0 is COLOUR

DGLOBAL_CACHE_SIZE = 1024*1024*10

-- background colour in non scroll mode: 8 = gray, 0 = white, 15 = black
DBACKGROUND_COLOR = 0

-- outer page colour in scroll mode: 8 = gray, 0 = white, 15 = black
DOUTER_PAGE_COLOR = 0

-- supported view mode includes: "scroll" and "page"
DCREREADER_VIEW_MODE = "page"

-- koptreader config defaults
DKOPTREADER_CONFIG_FONT_SIZE = 1.0		-- range from 0.1 to 3.0
DKOPTREADER_CONFIG_TEXT_WRAP = 0		-- 1 = on, 0 = off
DKOPTREADER_CONFIG_TRIM_PAGE = 1		-- 1 = auto, 0 = manual
DKOPTREADER_CONFIG_DETECT_INDENT = 1	-- 1 = enable, 0 = disable
DKOPTREADER_CONFIG_DEFECT_SIZE = 1.0	-- range from 0.0 to 3.0
DKOPTREADER_CONFIG_PAGE_MARGIN = 0.10	-- range from 0.0 to 1.0
DKOPTREADER_CONFIG_LINE_SPACING = 1.2	-- range from 0.5 to 2.0
DKOPTREADER_CONFIG_RENDER_QUALITY = 0.8	-- range from 0.5 to 1.0
DKOPTREADER_CONFIG_AUTO_STRAIGHTEN = 0	-- range from 0 to 10
DKOPTREADER_CONFIG_JUSTIFICATION = -1	-- -1 = auto, 0 = left, 1 = center, 2 = right, 3 = full
DKOPTREADER_CONFIG_MAX_COLUMNS = 2		-- range from 1 to 4
DKOPTREADER_CONFIG_CONTRAST = 1.0		-- range from 0.2 to 2.0

-- word spacing for reflow
DKOPTREADER_CONFIG_WORD_SAPCINGS = {0.05, 0.15, 0.375}  -- range from 0.05 to 0.5
DKOPTREADER_CONFIG_DEFAULT_WORD_SAPCING = 0.15			-- range from 0.05 to 0.5
-- document languages for OCR
DKOPTREADER_CONFIG_DOC_LANGS_TEXT = {"English", "Chinese_S", "Chinese_T"}
DKOPTREADER_CONFIG_DOC_LANGS_CODE = {"eng", "chi_sim", "chi_tra"}  -- ISO 639-3 language string, 
DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE = "eng"  -- and make sure you have corresponding training data 


-- ####################################################################
-- following features are not supported right now
-- ####################################################################

-- set panning distance
--DSHIFT_X = 100
--DSHIFT_Y = 50

-- step to change zoom manually, default = 16%
--DSTEP_MANUAL_ZOOM = 16
--DPAN_BY_PAGE = false -- using shift_[xy] or width/height
--DPAN_MARGIN = 5 -- horizontal margin for two-column zoom (in pixels)
--DPAN_OVERLAP_VERTICAL = 30

-- tile cache configuration:
--DCACHE_MAX_MEMSIZE = 1024*1024*5 -- 5MB tile cache
--DCACHE_MAX_TTL = 20 -- time to live

-- renderer cache size
--DCACHE_DOCUMENT_SIZE = 1024*1024*8 -- FIXME random, needs testing

-- default value for battery level logging
--DBATTERY_LOGGING = false


-- delay for info messages in ms
--DINFO_NODELAY=0
--DINFO_DELAY=1500

-- toggle defaults
--DUNIREADER_SHOW_OVERLAP_ENABLE = true
--DUNIREADER_SHOW_LINKS_ENABLE = true
--DUNIREADER_COMICS_MODE_ENABLE = true
--DUNIREADER_RTL_MODE_ENABLE = false
--DUNIREADER_PAGE_MODE_ENABLE = false

--DDJVUREADER_SHOW_OVERLAP_ENABLE = true
--DDJVUREADER_SHOW_LINKS_ENABLE = false
--DDJVUREADER_COMICS_MODE_ENABLE = true
--DDJVUREADER_RTL_MODE_ENABLE = false
--DDJVUREADER_PAGE_MODE_ENABLE = false

--DKOPTREADER_SHOW_OVERLAP_ENABLE = true
--DKOPTREADER_SHOW_LINKS_ENABLE = false
--DKOPTREADER_COMICS_MODE_ENABLE = false
--DKOPTREADER_RTL_MODE_ENABLE = false
--DKOPTREADER_PAGE_MODE_ENABLE = false

--DPICVIEWER_SHOW_OVERLAP_ENABLE = false
--DPICVIEWER_SHOW_LINKS_ENABLE = false
--DPICVIEWER_COMICS_MODE_ENABLE = true
--DPICVIEWER_RTL_MODE_ENABLE = false
--DPICVIEWER_PAGE_MODE_ENABLE = false


--DKOPTREADER_CONFIG_MULTI_THREADS = 1	-- 1 = on, 0 = off
--DKOPTREADER_CONFIG_SCREEN_ROTATION = 0	-- 0, 90, 180, 270 degrees
