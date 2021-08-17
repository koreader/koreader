-- To make configuration changes that persists between (nightly) releases,
-- copy defaults.lua to defaults.persistent.lua and make the changes there.

-- number of page turns between full screen refresh
-- default to do a full refresh on every 6 page turns
-- no longer needed
--DRCOUNTMAX = 6

-- number of pages for hinting
-- default to pre-rendering 1 page
DHINTCOUNT = 1

-- full screen mode, 1 for true, 0 for false
-- no longer needed
--DFULL_SCREEN = 1

-- scroll mode, 1 for true, 0 for false
-- no longer needed
--DSCROLL_MODE = 1

-- default gamma setting:
-- no longer needed
--DGLOBALGAMMA = 1.0

-- DjVu page rendering mode (used in djvu.c:drawPage())
-- See comments in djvureader.lua:DJVUReader:select_render_mode()
DRENDER_MODE = 0 -- 0 is COLOUR

-- minimum cache size
DGLOBAL_CACHE_SIZE_MINIMUM = 1024*1024*16

-- proportion of system free memory used as global cache
DGLOBAL_CACHE_FREE_PROPORTION = 0.4

-- maximum cache size
DGLOBAL_CACHE_SIZE_MAXIMUM = 1024*1024*64

-- background colour in non scroll mode: 8 = gray, 0 = white, 15 = black
DBACKGROUND_COLOR = 0

-- outer page colour in scroll mode: 8 = gray, 0 = white, 15 = black
DOUTER_PAGE_COLOR = 0

-- generic icon size
DGENERIC_ICON_SIZE = 40

-- supported view mode includes: "scroll" and "page"
DCREREADER_VIEW_MODE = "page"

-- show dimmed area to indicate page overlap in "page" view mode,
-- default to false
DSHOWOVERLAP = false

-- show hidden files in filemanager
-- default to false
DSHOWHIDDENFILES = false

-- landscape clockwise rotation
-- default to true, set to false for counterclockwise rotation
DLANDSCAPE_CLOCKWISE_ROTATION = true

-- default minimum screen height for reading with 2 pages in landscape mode
DCREREADER_TWO_PAGE_THRESHOLD = 7

-- page overlap pixels
DOVERLAPPIXELS = 30

-- timeout to show link rectangle around links
-- default to 0.5 second
-- set to 0 to disable showing rectangle and follow link immediately
FOLLOW_LINK_TIMEOUT = 0.5

-- customizable tap zones(rectangles)
-- x: x coordinate of top left corner in proportion to screen width
-- y: y coordinate of top left corner in proportion to screen height
-- w: tap zone width in proportion to screen width
-- h: tap zone height in proportion to screen height
DTAP_ZONE_MENU = {x = 0, y = 0, w = 1, h = 1/8}
DTAP_ZONE_MENU_EXT = {x = 1/4, y = 0, w = 2/4, h = 1/5} -- taller, narrower extension
DTAP_ZONE_CONFIG = {x = 0, y = 7/8, w = 1, h = 1/8}
DTAP_ZONE_CONFIG_EXT = {x = 1/4, y = 4/5, w = 2/4, h = 1/5} -- taller, narrower extension
DTAP_ZONE_MINIBAR = {x = 0, y = 12/13, w = 1, h = 1/13}
DTAP_ZONE_FORWARD = {x = 1/4, y = 0, w = 3/4, h = 1}
DTAP_ZONE_BACKWARD = {x = 0, y = 0, w = 1/4, h = 1}
-- DTAP_ZONE_BOOKMARK = {x = 7/8, y = 0, w = 1/8, h = 1/8} -- deprecated
-- DTAP_ZONE_FLIPPING = {x = 0, y = 0, w = 1/8, h = 1/8} -- deprecated
DTAP_ZONE_TOP_LEFT = {x = 0, y = 0, w = 1/8, h = 1/8}
DTAP_ZONE_TOP_RIGHT = {x = 7/8, y = 0, w = 1/8, h = 1/8}
DTAP_ZONE_BOTTOM_LEFT = {x = 0, y = 7/8, w = 1/8, h = 1/8}
DTAP_ZONE_BOTTOM_RIGHT = {x = 7/8, y = 7/8, w = 1/8, h = 1/8}
DDOUBLE_TAP_ZONE_NEXT_CHAPTER = {x = 1/4, y = 0, w = 3/4, h = 1}
DDOUBLE_TAP_ZONE_PREV_CHAPTER = {x = 0, y = 0, w = 1/4, h = 1}

-- behaviour of swipes
DCHANGE_WEST_SWIPE_TO_EAST = false
DCHANGE_EAST_SWIPE_TO_WEST = false

-- koptreader config defaults
DKOPTREADER_CONFIG_FONT_SIZE = 1.0        -- range from 0.1 to 3.0
DKOPTREADER_CONFIG_TEXT_WRAP = 0        -- 1 = on, 0 = off
DKOPTREADER_CONFIG_TRIM_PAGE = 1        -- 1 = auto, 0 = manual
DKOPTREADER_CONFIG_DETECT_INDENT = 1    -- 1 = enable, 0 = disable
DKOPTREADER_CONFIG_DEFECT_SIZE = 1.0    -- range from 0.0 to 3.0
DKOPTREADER_CONFIG_PAGE_MARGIN = 0.10    -- range from 0.0 to 1.0
DKOPTREADER_CONFIG_LINE_SPACING = 1.2    -- range from 0.5 to 2.0
DKOPTREADER_CONFIG_RENDER_QUALITY = 1.0    -- range from 0.5 to 2.0
DKOPTREADER_CONFIG_AUTO_STRAIGHTEN = 0    -- range from 0 to 10
DKOPTREADER_CONFIG_JUSTIFICATION = 3    -- -1 = auto, 0 = left, 1 = center, 2 = right, 3 = full
DKOPTREADER_CONFIG_MAX_COLUMNS = 2        -- range from 1 to 4
DKOPTREADER_CONFIG_CONTRAST = 1.0        -- range from 0.2 to 2.0

-- word spacing for reflow
DKOPTREADER_CONFIG_WORD_SPACINGS = {0.05, -0.2, 0.375}    -- range from (+/-)0.05 to (+/-)0.5
DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING = -0.2            -- range from (+/-)0.05 to (+/-)0.5
-- document languages for OCR
DKOPTREADER_CONFIG_DOC_LANGS_TEXT = {"English", "Chinese"}
DKOPTREADER_CONFIG_DOC_LANGS_CODE = {"eng", "chi_sim"}    -- language code, make sure you have corresponding training data
DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE = "eng"          -- that have filenames starting with the language codes

-- crereader font sizes
-- feel free to add more entries in this list
DCREREADER_CONFIG_FONT_SIZES = {12, 16, 20, 22, 24, 26, 28, 30, 34, 38, 44}  -- option range from 12 to 44
DCREREADER_CONFIG_DEFAULT_FONT_SIZE = 22    -- default font size

-- crereader margin sizes
-- horizontal margins {left, right} in (relative) pixels
DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL = {5, 5}
DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM = {10, 10}
DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE = {15, 15}
DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE = {20, 20}
DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE = {30, 30}
DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE = {50, 50}
DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE = {70, 70}
DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE = {100, 100}
DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE = {140, 140}

-- top margin in (relative) pixels
DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL = 5
DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM = 10
DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE = 15
DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE = 20
DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE = 30
DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE = 50
DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE = 70
DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE = 100
DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE = 140

-- bottom margin in (relative) pixels
DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL = 5
DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM = 10
DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE = 15
DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE = 20
DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE = 30
DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE = 50
DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE = 70
DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE = 100
DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE = 140

-- crereader font gamma (no longer used)
-- DCREREADER_CONFIG_LIGHTER_FONT_GAMMA = 10
-- DCREREADER_CONFIG_DEFAULT_FONT_GAMMA = 15
-- DCREREADER_CONFIG_DARKER_FONT_GAMMA = 25

-- crereader line space percentage
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY = 70
DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY = 75
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL = 80
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL = 85
DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL = 90
DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL = 95
DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM = 100
DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM = 105
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM = 110
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM = 115
DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE = 120
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE = 125
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE = 130

-- word spacing percentages
-- 1st number scales the normal width of spaces in all font
--     (100% uses the font space width untouched)
-- 2nd number applies after the 1st has been applied, and
--     tells how much these spaces can additionally be condensed
--     to make more text fit on a line.
-- So, {80,50} can reduce the width of a space up to 40% of its
-- regular width. {99, 100} allows reducing it by at least 1px.
-- (These replace the old settings DCREREADER_CONFIG_WORD_GAP_*,
-- with the equivalence: new_option = { 100, old_option }.)
DCREREADER_CONFIG_WORD_SPACING_SMALL = {75, 50}
DCREREADER_CONFIG_WORD_SPACING_MEDIUM = {95, 75}
DCREREADER_CONFIG_WORD_SPACING_LARGE = {100, 90}

-- word expansion, to reduce excessive spacing on justified line
-- by using letter spacing on the words
-- value is the max allowed added letter spacing, as a % of the font size
DCREREADER_CONFIG_WORD_EXPANSION_NONE = 0
DCREREADER_CONFIG_WORD_EXPANSION_SOME = 5
DCREREADER_CONFIG_WORD_EXPANSION_MORE = 15

-- crereader progress bar (no longer needed)
-- 0 for top "full" progress bar
-- 1 for bottom "mini" progress bar
--DCREREADER_PROGRESS_BAR = 1

-- configure "mini" progress bar
-- no longer needed
--DMINIBAR_TOC_MARKER_WIDTH = 2   -- Looses usefulness > 3
DMINIBAR_CONTAINER_HEIGHT = 14  -- Larger means more padding at the bottom, at the risk of eating into the last line
-- no longer needed
--DMINIBAR_FONT_SIZE = 14
-- no longer needed
--DMINIBAR_HEIGHT = 7             -- Should be smaller than DMINIBAR_CONTAINER_HEIGHT

-- change this to any numerical value if you want to automatically save settings when turning pages
-- no longer needed (now available in menu as an interval in minutes)
-- DAUTO_SAVE_PAGING_COUNT = nil

-- dictionary font size
-- no longer needed
--DDICT_FONT_SIZE = 20

-- Frontlight decrease of sensitivity for two-fingered pan gesture,
-- e.g. 2 changes the sensitivity by 1/2, 3 by 1/3 etc.
FRONTLIGHT_SENSITIVITY_DECREASE = 2

-- Normally, KOReader will present file lists sorted in case insensitive manner
-- when presenting an alphatically sorted list. So the Order is "A, b, C, d".
-- You can switch to a case sensitive sort ("A", "C", "b", "d") by disabling
-- insensitive sort
DALPHA_SORT_CASE_INSENSITIVE = true

-- no longer needed
-- Set a path to a folder that is filled by Calibre (must contain the file metadata.calibre)
-- e.g.
-- "/mnt/sd/.hidden" for Kobo with files in ".hidden" on the SD card
-- "/mnt/onboard/MyPath" for Kobo with files in "MyPath" on the device itself
-- "/mnt/us/documents/" for Kindle files in folder "documents"
--SEARCH_LIBRARY_PATH  = ""
--SEARCH_LIBRARY_PATH2 = ""
--
-- Search parameters
--SEARCH_CASESENSITIVE = false
--
--SEARCH_AUTHORS = true
--SEARCH_TITLE = true
--SEARCH_TAGS = true
--SEARCH_SERIES = true
--SEARCH_PATH = true

-- Light parameter for Kobo
KOBO_LIGHT_ON_START = -2           -- -1, -2 or 0-100.
                                   -- -1 uses previous koreader session saved brightness
                                   -- -2 uses 'Kobo eReader.conf' brighness,
                                   -- other sets light on start to a fix brighness
KOBO_SYNC_BRIGHTNESS_WITH_NICKEL = true  -- Save brightness set in KOreader
                                         -- with nickel's 'Kobo eReader.conf'

-- Network proxy settings
-- proxy url should be a string in the format of "http://localhost:3128"
-- proxy authentication is not supported yet.
NETWORK_PROXY = nil

-- Experimental features
-- Use turbo library to handle async HTTP request
DUSE_TURBO_LIB = false

-- Absolute path to stardict files (override)
-- By default they're stored in data/dict under dataDir.
STARDICT_DATA_DIR = nil

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


--DKOPTREADER_CONFIG_MULTI_THREADS = 1    -- 1 = on, 0 = off
--DKOPTREADER_CONFIG_SCREEN_ROTATION = 0    -- 0, 90, 180, 270 degrees
