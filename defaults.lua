-- To make configuration changes that persists between (nightly) releases,
-- copy defaults.lua to defaults.custom.lua and make the changes there,
-- or go to [Tools] > More tools > Advanced settings in the filemanager.

return {
-- number of pages for hinting
-- default to pre-rendering 1 page (pair)
--
-- When using Dual Page Mode, this controls the amount of next page
-- pairs that will be pre-rednered.
DHINTCOUNT = 1,

-- DjVu page rendering mode (used in djvu.c:drawPage())
-- See comments in djvureader.lua:DJVUReader:select_render_mode()
DRENDER_MODE = 0, -- 0 is COLOUR

-- minimum cache size
DGLOBAL_CACHE_SIZE_MINIMUM = 1024*1024*16,

-- proportion of system free memory used as global cache
DGLOBAL_CACHE_FREE_PROPORTION = 0.4,

-- maximum cache size
DGLOBAL_CACHE_SIZE_MAXIMUM = 1024*1024*512,

-- background colour in non scroll mode: 8 = gray, 0 = white, 15 = black
DBACKGROUND_COLOR = 0,

-- outer page colour in scroll mode: 8 = gray, 0 = white, 15 = black
DOUTER_PAGE_COLOR = 0,

-- generic icon size
DGENERIC_ICON_SIZE = 40,

-- supported view mode includes: "scroll" and "page"
DCREREADER_VIEW_MODE = "page",

-- show dimmed area to indicate page overlap in "page" view mode,
-- default to false
DSHOWOVERLAP = false,

-- default minimum screen height for reading with 2 pages in landscape mode
DCREREADER_TWO_PAGE_THRESHOLD = 7,

-- page overlap pixels
DOVERLAPPIXELS = 30,

-- timeout to show link rectangle around links
-- default to 0.5 second
-- set to 0 to disable showing rectangle and follow link immediately
FOLLOW_LINK_TIMEOUT = 0.5,

-- customizable tap zones(rectangles)
-- x: x coordinate of top left corner in proportion to screen width
-- y: y coordinate of top left corner in proportion to screen height
-- w: tap zone width in proportion to screen width
-- h: tap zone height in proportion to screen height
DTAP_ZONE_MENU = {x = 0, y = 0, w = 1, h = 1/8},
DTAP_ZONE_MENU_EXT = {x = 1/4, y = 0, w = 2/4, h = 1/5}, -- taller, narrower extension
DTAP_ZONE_CONFIG = {x = 0, y = 7/8, w = 1, h = 1/8},
DTAP_ZONE_CONFIG_EXT = {x = 1/4, y = 4/5, w = 2/4, h = 1/5}, -- taller, narrower extension
DTAP_ZONE_MINIBAR = {x = 0, y = 12/13, w = 1, h = 1/13},
DTAP_ZONE_FORWARD = {x = 1/4, y = 0, w = 3/4, h = 1},
DTAP_ZONE_BACKWARD = {x = 0, y = 0, w = 1/4, h = 1},
DTAP_ZONE_TOP_LEFT = {x = 0, y = 0, w = 1/8, h = 1/8},
DTAP_ZONE_TOP_RIGHT = {x = 7/8, y = 0, w = 1/8, h = 1/8},
DTAP_ZONE_BOTTOM_LEFT = {x = 0, y = 7/8, w = 1/8, h = 1/8},
DTAP_ZONE_BOTTOM_RIGHT = {x = 7/8, y = 7/8, w = 1/8, h = 1/8},
DDOUBLE_TAP_ZONE_NEXT_CHAPTER = {x = 1/4, y = 0, w = 3/4, h = 1},
DDOUBLE_TAP_ZONE_PREV_CHAPTER = {x = 0, y = 0, w = 1/4, h = 1},
DSWIPE_ZONE_LEFT_EDGE = { x = 0, y = 0, w = 1/8, h = 1},
DSWIPE_ZONE_RIGHT_EDGE = { x = 7/8, y = 0, w = 1/8, h = 1},
DSWIPE_ZONE_TOP_EDGE = { x = 0, y = 0, w = 1, h = 1/8},
DSWIPE_ZONE_BOTTOM_EDGE = { x = 0, y = 7/8, w = 1, h = 1/8},

-- koptreader config defaults
DKOPTREADER_CONFIG_FONT_SIZE = 1.0,        -- range from 0.1 to 3.0
DKOPTREADER_CONFIG_TEXT_WRAP = 0,        -- 1 = on, 0 = off
DKOPTREADER_CONFIG_TRIM_PAGE = 1,        -- 1 = auto, 0 = manual
DKOPTREADER_CONFIG_DETECT_INDENT = 1,    -- 1 = enable, 0 = disable
DKOPTREADER_CONFIG_DEFECT_SIZE = 1.0,    -- range from 0.0 to 3.0
DKOPTREADER_CONFIG_PAGE_MARGIN = 0.10,    -- range from 0.0 to 1.0
DKOPTREADER_CONFIG_LINE_SPACING = 1.2,    -- range from 0.5 to 2.0
DKOPTREADER_CONFIG_RENDER_QUALITY = 1.0,    -- range from 0.5 to 2.0
DKOPTREADER_CONFIG_AUTO_STRAIGHTEN = 0,    -- range from 0 to 10
DKOPTREADER_CONFIG_JUSTIFICATION = 3,    -- -1 = auto, 0 = left, 1 = center, 2 = right, 3 = full
DKOPTREADER_CONFIG_MAX_COLUMNS = 2,        -- range from 1 to 4
DKOPTREADER_CONFIG_CONTRAST = 1.0,        -- range from 0.2 to 2.0

-- word spacing for reflow
DKOPTREADER_CONFIG_WORD_SPACINGS = {0.05, -0.2, 0.375},    -- range from (+/-)0.05 to (+/-)0.5
DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING = -0.2,            -- range from (+/-)0.05 to (+/-)0.5
-- document languages for OCR
DKOPTREADER_CONFIG_DOC_LANGS_CODE = {"eng", "chi_sim"},    -- language code, make sure you have corresponding training data
DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE = "eng",          -- that have filenames starting with the language codes

-- crereader font sizes
-- feel free to add more entries in this list
DCREREADER_CONFIG_FONT_SIZES = {12, 16, 20, 22, 24, 26, 28, 30, 34, 38, 44},  -- option range from 12 to 44
DCREREADER_CONFIG_DEFAULT_FONT_SIZE = 22,    -- default font size

-- crereader margin sizes
-- horizontal margins {left, right} in (relative) pixels
DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL = {5, 5},
DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM = {10, 10},
DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE = {15, 15},
DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE = {20, 20},
DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE = {30, 30},
DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE = {50, 50},
DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE = {70, 70},
DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE = {100, 100},
DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE = {140, 140},

-- top margin in (relative) pixels
DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL = 5,
DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM = 10,
DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE = 15,
DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE = 20,
DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE = 30,
DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE = 50,
DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE = 70,
DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE = 100,
DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE = 140,

-- bottom margin in (relative) pixels
DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL = 5,
DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM = 10,
DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE = 15,
DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE = 20,
DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE = 30,
DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE = 50,
DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE = 70,
DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE = 100,
DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE = 140,

-- crereader line space percentage
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY = 70,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY = 75,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL = 80,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL = 85,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL = 90,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL = 95,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM = 100,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM = 105,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM = 110,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM = 115,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE = 120,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE = 125,
DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE = 130,

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
DCREREADER_CONFIG_WORD_SPACING_SMALL = {75, 50},
DCREREADER_CONFIG_WORD_SPACING_MEDIUM = {95, 75},
DCREREADER_CONFIG_WORD_SPACING_LARGE = {100, 90},

-- word expansion, to reduce excessive spacing on justified line
-- by using letter spacing on the words
-- value is the max allowed added letter spacing, as a % of the font size
DCREREADER_CONFIG_WORD_EXPANSION_NONE = 0,
DCREREADER_CONFIG_WORD_EXPANSION_SOME = 5,
DCREREADER_CONFIG_WORD_EXPANSION_MORE = 15,

-- configure "mini" progress bar
DMINIBAR_CONTAINER_HEIGHT = 14,  -- Larger means more padding at the bottom, at the risk of eating into the last line

-- Normally, KOReader will present file lists sorted in case insensitive manner
-- when presenting an alphatically sorted list. So the Order is "A, b, C, d".
-- You can switch to a case sensitive sort ("A", "C", "b", "d") by disabling
-- insensitive sort
DALPHA_SORT_CASE_INSENSITIVE = true,

-- Frontlight behavior on Kobo
KOBO_LIGHT_ON_START = -2,          -- -1, -2 or 0-100.
                                   -- -1 uses the brightness set by KOReader (if any, 20% otherwise)
                                   -- -2 uses the brightness set in Nickel
KOBO_SYNC_BRIGHTNESS_WITH_NICKEL = true,  -- Update Nickel's config to match our own

-- Network proxy settings
-- proxy url should be a string in the format of "http://localhost:3128"
-- proxy authentication is not supported yet.
NETWORK_PROXY = nil,

-- Experimental features
-- Use turbo library to handle async HTTP request
DUSE_TURBO_LIB = false,

-- Absolute path to stardict files (override)
-- By default they're stored in data/dict under dataDir.
STARDICT_DATA_DIR = nil,
}
