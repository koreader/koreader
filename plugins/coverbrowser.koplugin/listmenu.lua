local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template
local getMenuText = require("ui/widget/menu").getMenuText

local BookInfoManager = require("bookinfomanager")

-- Here is the specific UI implementation for "list" display modes
-- (see covermenu.lua for the generic code)

-- We will show a rotated dogear at bottom right corner of cover widget for
-- opened files (the dogear will make it look like a "used book")
-- The ImageWidget Will be created when we know the available height (and
-- recreated if height changes)
local corner_mark_size = -1
local corner_mark

local scale_by_size = Screen:scaleBySize(1000000) * (1/1000000)

-- ItemShortCutIcon (for keyboard navigation) is private to menu.lua and can't be accessed,
-- so we need to redefine it
local ItemShortCutIcon = WidgetContainer:extend{
    dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
    key = nil,
    bordersize = Size.border.default,
    radius = 0,
    style = "square",
}

function ItemShortCutIcon:init()
    if not self.key then
        return
    end
    local radius = 0
    local background = Blitbuffer.COLOR_WHITE
    if self.style == "rounded_corner" then
        radius = math.floor(self.width/2)
    elseif self.style == "grey_square" then
        background = Blitbuffer.COLOR_LIGHT_GRAY
    end
    local sc_face
    if self.key:len() > 1 then
        sc_face = Font:getFace("ffont", 14)
    else
        sc_face = Font:getFace("scfont", 22)
    end
    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = self.bordersize,
        radius = radius,
        background = background,
        dimen = self.dimen:copy(),
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{
                text = self.key,
                face = sc_face,
            },
        },
    }
end


-- Based on menu.lua's MenuItem
local ListMenuItem = InputContainer:extend{
    entry = nil, -- hash, mandatory
    text = nil,
    show_parent = nil,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    _underline_container = nil,
    do_cover_image = false,
    do_filename_only = false,
    do_hint_opened = false,
    been_opened = false,
    init_done = false,
    bookinfo_found = false,
    cover_specs = nil,
    has_description = false,
}

function ListMenuItem:init()
    -- filepath may be provided as 'file' (history, collection) or 'path' (filechooser)
    -- store it as attribute so we can use it elsewhere
    self.filepath = self.entry.file or self.entry.path

    -- As done in MenuItem
    -- Squared letter for keyboard navigation
    if self.shortcut then
        local icon_width = math.floor(self.dimen.h*2/5)
        local shortcut_icon_dimen = Geom:new{
            x = 0,
            y = 0,
            w = icon_width,
            h = icon_width,
        }
        -- To keep a simpler widget structure, this shortcut icon will not
        -- be part of it, but will be painted over the widget in our paintTo
        self.shortcut_icon = ItemShortCutIcon:new{
            dimen = shortcut_icon_dimen,
            key = self.shortcut,
            style = self.shortcut_style,
        }
    end

    -- we need this table per-instance, so we declare it here
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }

    -- We now build the minimal widget container that won't change after update()

    -- As done in MenuItem
    -- for compatibility with keyboard navigation
    -- (which does not seem to work well when multiple pages,
    -- even with classic menu)
    self.underline_h = 1 -- smaller than default (3) to not shift our vertical alignment
    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = Geom:new{
            w = self.width,
            h = self.height
        },
        linesize = self.underline_h,
        -- widget : will be filled in self:update()
    }
    self[1] = self._underline_container

    -- Remaining part of initialization is done in update(), because we may
    -- have to do it more than once if item not found in db
    self:update()
    self.init_done = true
end

function ListMenuItem:update()
    -- We will be a distinctive widget whether we are a directory,
    -- a known file with image / without image, or a not yet known file
    local widget

    -- we'll add a VerticalSpan of same size as underline container for balance
    local dimen = Geom:new{
        w = self.width,
        h = self.height - 2 * self.underline_h
    }

    local function _fontSize(nominal, max)
        -- The nominal font size is based on 64px ListMenuItem height.
        -- Keep ratio of font size to item height
        local font_size = math.floor(nominal * dimen.h * (1/64) / scale_by_size)
        -- But limit it to the provided max, to avoid huge font size when
        -- only 4-6 items per page
        if max and font_size >= max then
            return max
        end
        return font_size
    end
    -- Will speed up a bit if we don't do all font sizes when
    -- looking for one that make text fit
    local fontsize_dec_step = math.ceil(_fontSize(100) * (1/100))

    -- We'll draw a border around cover images, it may not be
    -- needed with some covers, but it's nicer when cover is
    -- a pure white background (like rendered text page)
    local border_size = Size.border.thin
    local max_img_w = dimen.h - 2*border_size -- width = height, squared
    local max_img_h = dimen.h - 2*border_size
    local cover_specs = {
        max_cover_w = max_img_w,
        max_cover_h = max_img_h,
    }
    -- Make it available to our menu, for batch extraction
    -- to know what size is needed for current view
    if self.do_cover_image then
        self.menu.cover_specs = cover_specs
    else
        self.menu.cover_specs = false
    end

    self.is_directory = not (self.entry.is_file or self.entry.file)
    if self.is_directory then
        -- nb items on the right, directory name on the left
        local wright = TextWidget:new{
            text = self.mandatory or "",
            face = Font:getFace("infont", _fontSize(14, 18)),
        }
        local pad_width = Screen:scaleBySize(10) -- on the left, in between, and on the right
        local wleft_width = dimen.w - wright:getWidth() - 3*pad_width
        local wleft = TextBoxWidget:new{
            text = BD.directory(self.text),
            face = Font:getFace("cfont", _fontSize(20, 24)),
            width = wleft_width,
            alignment = "left",
            bold = true,
            height = dimen.h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
        widget = OverlapGroup:new{
            dimen = dimen:copy(),
            LeftContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = pad_width },
                    wleft,
                }
            },
            RightContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    wright,
                    HorizontalSpan:new{ width = pad_width },
                },
            },
        }
    else -- file
        self.file_deleted = self.entry.dim -- entry with deleted file from History or selected file from FM
        local fgcolor = self.file_deleted and Blitbuffer.COLOR_DARK_GRAY or nil

        local bookinfo = BookInfoManager:getBookInfo(self.filepath, self.do_cover_image)

        if bookinfo and self.do_cover_image and not bookinfo.ignore_cover and not self.file_deleted then
            if bookinfo.cover_fetched then
                if bookinfo.has_cover and not self.menu.no_refresh_covers then
                    if BookInfoManager.isCachedCoverInvalid(bookinfo, cover_specs) then
                        -- there is a thumbnail, but it's smaller than is needed for new grid dimensions,
                        -- and it would be ugly if scaled up to the required size:
                        -- do as if not found to force a new extraction with our size
                        if bookinfo.cover_bb then
                            bookinfo.cover_bb:free()
                        end
                        bookinfo = nil
                    end
                end
                -- if not has_cover, book has no cover, no need to try again
            else
                -- cover was not fetched previously, do as if not found
                -- to force a new extraction
                bookinfo = nil
            end
        end

        if bookinfo then -- This book is known
            self.bookinfo_found = true
            local cover_bb_used = false

            -- Build the left widget : image if wanted
            local wleft = nil
            local wleft_width = 0 -- if not do_cover_image
            local wleft_height
            if self.do_cover_image then
                wleft_height = dimen.h
                wleft_width = wleft_height -- make it squared
                if bookinfo.has_cover and not bookinfo.ignore_cover then
                    cover_bb_used = true
                    -- Let ImageWidget do the scaling and give us the final size
                    local _, _, scale_factor = BookInfoManager.getCachedCoverSize(bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)
                    local wimage = ImageWidget:new{
                        image = bookinfo.cover_bb,
                        scale_factor = scale_factor,
                    }
                    wimage:_render()
                    local image_size = wimage:getSize() -- get final widget size
                    wleft = CenterContainer:new{
                        dimen = Geom:new{ w = wleft_width, h = wleft_height },
                        FrameContainer:new{
                            width = image_size.w + 2*border_size,
                            height = image_size.h + 2*border_size,
                            margin = 0,
                            padding = 0,
                            bordersize = border_size,
                            dim = self.file_deleted,
                            wimage,
                        }
                    }
                    -- Let menu know it has some item with images
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
                else
                    local fake_cover_w = max_img_w * 0.6
                    local fake_cover_h = max_img_h
                    wleft = CenterContainer:new{
                        dimen = Geom:new{ w = wleft_width, h = wleft_height },
                        FrameContainer:new{
                            width = fake_cover_w + 2*border_size,
                            height = fake_cover_h + 2*border_size,
                            margin = 0,
                            padding = 0,
                            bordersize = border_size,
                            dim = self.file_deleted,
                            CenterContainer:new{
                                dimen = Geom:new{ w = fake_cover_w, h = fake_cover_h },
                                TextWidget:new{
                                    text = "⛶", -- U+26F6 Square four corners
                                    face = Font:getFace("cfont",  _fontSize(20)),
                                },
                            },
                        },
                    }
                end
            end
            -- In case we got a blitbuffer and didn't use it (ignore_cover), free it
            if bookinfo.cover_bb and not cover_bb_used then
                bookinfo.cover_bb:free()
            end
            -- So we can draw an indicator if this book has a description
            if bookinfo.description then
                self.has_description = true
            end

            -- Gather some info, mostly for right widget:
            --   file size (self.mandatory) (not available with History)
            --   file type
            --   pages read / nb of pages (not available for crengine doc not opened)
            -- Current page / pages are available or more accurate in .sdr/metadata.lua
            -- We use a cache (cleaned at end of this browsing session) to store
            -- page, percent read and book status from sidecar files, to avoid
            -- re-parsing them when re-rendering a visited page
            if not self.menu.cover_info_cache then
                self.menu.cover_info_cache = {}
            end
            local pages_str = ""
            local pages = bookinfo.pages -- default to those in bookinfo db
            local percent_finished, status, has_highlight
            if DocSettings:hasSidecarFile(self.filepath) then
                self.been_opened = true
                self.menu:updateCache(self.filepath, nil, true, pages) -- create new cache entry if absent
                pages, percent_finished, status, has_highlight =
                    unpack(self.menu.cover_info_cache[self.filepath], 1, self.menu.cover_info_cache[self.filepath].n)
            end
            -- right widget, first line
            local directory, filename = util.splitFilePathName(self.filepath) -- luacheck: no unused
            local filename_without_suffix, filetype = filemanagerutil.splitFileNameType(filename)
            local fileinfo_str
            if bookinfo._no_provider then
                -- for unsupported files: don't show extension on the right,
                -- keep it in filename
                filename_without_suffix = filename
                fileinfo_str = self.mandatory
            else
                local mark = has_highlight and "\u{2592}  " or "" -- "medium shade"
                fileinfo_str = mark .. BD.wrap(filetype) .. "  " .. BD.wrap(self.mandatory)
            end
            -- right widget, second line
            if status == "complete" or status == "abandoned" then
                -- Display these instead of the read %
                if pages then
                    if status == "complete" then
                        pages_str = T(N_("Finished – 1 page", "Finished – %1 pages", pages), pages)
                    else
                        pages_str = T(N_("On hold – 1 page", "On hold – %1 pages", pages), pages)
                    end
                else
                    pages_str = status == "complete" and _("Finished") or _("On hold")
                end
            elseif percent_finished then
                if pages then
                    if BookInfoManager:getSetting("show_pages_read_as_progress") then
                        pages_str = T(_("Page %1 of %2"), Math.round(percent_finished*pages), pages)
                    else
                        pages_str = T(_("%1 % of %2 pages"), math.floor(100*percent_finished), pages)
                    end
                    if BookInfoManager:getSetting("show_pages_left_in_progress") then
                        pages_str = T(_("%1, %2 to read"), pages_str, Math.round(pages-percent_finished*pages), pages)
                    end
                else
                    pages_str = string.format("%d %%", 100*percent_finished)
                end
            else
                if pages then
                    pages_str = T(N_("1 page", "%1 pages", pages), pages)
                end
            end

            -- Build the right widget

            local fontsize_info = _fontSize(14, 18)

            local wright_items = {align = "right"}
            local wright_right_padding = 0
            local wright_width = 0
            local wright

            if not BookInfoManager:getSetting("hide_file_info") then
                local wfileinfo = TextWidget:new{
                    text = fileinfo_str,
                    face = Font:getFace("cfont", fontsize_info),
                    fgcolor = fgcolor,
                }
                table.insert(wright_items, wfileinfo)
            end

            if not BookInfoManager:getSetting("hide_page_info") then
                local wpageinfo = TextWidget:new{
                    text = pages_str,
                    face = Font:getFace("cfont", fontsize_info),
                    fgcolor = fgcolor,
                }
                table.insert(wright_items, wpageinfo)
            end

            if #wright_items > 0 then
                for i, w in ipairs(wright_items) do
                    wright_width = math.max(wright_width, w:getSize().w)
                end
                wright = CenterContainer:new{
                    dimen = Geom:new{ w = wright_width, h = dimen.h },
                    VerticalGroup:new(wright_items),
                }
                wright_right_padding = Screen:scaleBySize(10)
            end

            -- Create or replace corner_mark if needed
            local mark_size = math.floor(dimen.h * (1/6))
            -- Just fits under the page info text, which in turn adapts to the ListMenuItem height.
            if mark_size ~= corner_mark_size then
                corner_mark_size = mark_size
                if corner_mark then
                    corner_mark:free()
                end
                corner_mark = IconWidget:new{
                    icon = "dogear.opaque",
                    rotation_angle = BD.mirroredUILayout() and 180 or 270,
                    width = corner_mark_size,
                    height = corner_mark_size,
                }
            end

            -- Build the middle main widget, in the space available
            local wmain_left_padding = Screen:scaleBySize(10)
            if self.do_cover_image then
                -- we need less padding, as cover image, most often in
                -- portrait mode, will provide some padding
                wmain_left_padding = Screen:scaleBySize(5)
            end
            local wmain_right_padding = Screen:scaleBySize(10) -- used only for next calculation
            local wmain_width = dimen.w - wleft_width - wmain_left_padding - wmain_right_padding - wright_width - wright_right_padding

            local fontname_title = "cfont"
            local fontname_authors = "cfont"
            local fontsize_title = _fontSize(20, 24)
            local fontsize_authors = _fontSize(18, 22)
            local wtitle, wauthors
            local title, authors
            local series_mode = BookInfoManager:getSetting("series_mode")

            -- whether to use or not title and authors
            -- (We wrap each metadata text with BD.auto() to get for each of them
            -- the text direction from the first strong character - which should
            -- individually be the best thing, and additionally prevent shuffling
            -- if concatenated.)
            if self.do_filename_only or bookinfo.ignore_meta then
                title = filename_without_suffix -- made out above
                title = BD.auto(title)
                authors = nil
            else
                title = bookinfo.title and bookinfo.title or filename_without_suffix
                title = BD.auto(title)
                authors = bookinfo.authors
                -- If multiple authors (crengine separates them with \n), we
                -- can display them on multiple lines, but limit to 2, and
                -- append "et al." to the 2nd if there are more
                if authors and authors:find("\n") then
                    authors = util.splitToArray(authors, "\n")
                    for i=1, #authors do
                        authors[i] = BD.auto(authors[i])
                    end
                    if #authors > 1 and bookinfo.series and series_mode == "series_in_separate_line" then
                        authors = { T(_("%1 et al."), authors[1]) }
                    elseif #authors > 2 then
                        authors = { authors[1], T(_("%1 et al."), authors[2]) }
                    end
                    authors = table.concat(authors, "\n")
                    -- as we'll fit 3 lines instead of 2, we can avoid some loops by starting from a lower font size
                    fontsize_title = _fontSize(17, 21)
                    fontsize_authors = _fontSize(15, 19)
                elseif authors then
                    authors = BD.auto(authors)
                end
            end
            -- add Series metadata if requested
            if bookinfo.series then
                if bookinfo.series_index then
                    bookinfo.series = BD.auto(bookinfo.series .. " #" .. bookinfo.series_index)
                else
                    bookinfo.series = BD.auto(bookinfo.series)
                end
                if series_mode == "append_series_to_title" then
                    if title then
                        title = title .. " - " .. bookinfo.series
                    else
                        title = bookinfo.series
                    end
                end
                if not authors then
                    if series_mode == "append_series_to_authors" or series_mode == "series_in_separate_line" then
                        authors = bookinfo.series
                    end
                else
                    if series_mode == "append_series_to_authors" then
                        authors = authors .. " - " .. bookinfo.series
                    elseif series_mode == "series_in_separate_line" then
                        authors = bookinfo.series .. "\n" .. authors
                        -- as we'll fit 3 lines instead of 2, we can avoid some loops by starting from a lower font size
                        fontsize_title = _fontSize(17, 21)
                        fontsize_authors = _fontSize(15, 19)
                    end
                end
            end
            if bookinfo.unsupported then
                -- Let's show this fact in place of the anyway empty authors slot
                authors = T(_("(no book information: %1)"), _(bookinfo.unsupported))
            end
            -- Build title and authors texts with decreasing font size
            -- till it fits in the space available
            local build_title = function(height)
                if wtitle then
                    wtitle:free(true)
                    wtitle = nil
                end
                -- BookInfoManager:extractBookInfo() made sure
                -- to save as nil (NULL) metadata that were an empty string
                -- We provide the book language to get a chance to render title
                -- and authors with alternate glyphs for that language.
                wtitle = TextBoxWidget:new{
                    text = title,
                    lang = bookinfo.language,
                    face = Font:getFace(fontname_title, fontsize_title),
                    width = wmain_width,
                    height = height,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                    alignment = "left",
                    bold = true,
                    fgcolor = fgcolor,
                }
            end
            local build_authors = function(height)
                if wauthors then
                    wauthors:free(true)
                    wauthors = nil
                end
                wauthors = TextBoxWidget:new{
                    text = authors,
                    lang = bookinfo.language,
                    face = Font:getFace(fontname_authors, fontsize_authors),
                    width = wmain_width,
                    height = height,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                    alignment = "left",
                    fgcolor = fgcolor,
                }
            end
            while true do
                build_title()
                local height = wtitle:getSize().h
                if authors then
                    build_authors()
                    height = height + wauthors:getSize().h
                end
                if height <= dimen.h then
                    -- We fit!
                    break
                end
                -- Don't go too low, and get out of this loop.
                if fontsize_title <= 12 or fontsize_authors <= 10 then
                    local title_height = wtitle:getSize().h
                    local title_line_height = wtitle:getLineHeight()
                    local title_min_height = 2 * title_line_height -- unscaled_size_check: ignore
                    local authors_height = authors and wauthors:getSize().h or 0
                    local authors_line_height = authors and wauthors:getLineHeight() or 0
                    local authors_min_height = 2 * authors_line_height -- unscaled_size_check: ignore
                    -- Chop lines, starting with authors, until
                    -- both labels fit in the allocated space.
                    while title_height + authors_height > dimen.h do
                        if authors_height > authors_min_height then
                            authors_height = authors_height - authors_line_height
                        elseif title_height > title_min_height then
                            title_height = title_height - title_line_height
                        else
                            break
                        end
                    end
                    if title_height < wtitle:getSize().h then
                        build_title(title_height)
                    end
                    if authors and authors_height < wauthors:getSize().h then
                        build_authors(authors_height)
                    end
                    break
                end
                -- If we don't fit, decrease both font sizes
                fontsize_title = fontsize_title - fontsize_dec_step
                fontsize_authors = fontsize_authors - fontsize_dec_step
                logger.dbg(title, "recalculate title/author with", fontsize_title)
            end

            local wmain = LeftContainer:new{
                dimen = dimen:copy(),
                VerticalGroup:new{
                    wtitle,
                    wauthors,
                }
            }

            -- Build the final widget
            widget = OverlapGroup:new{
                dimen = dimen:copy(),
            }
            if self.do_cover_image then
                -- add left widget
                if wleft then
                    -- no need for left padding, as cover image, most often in
                    -- portrait mode, will have some padding - the rare landscape
                    -- mode cover image will be stuck to screen side thus
                    table.insert(widget, wleft)
                end
                -- pad main widget on the left with size of left widget
                wmain = HorizontalGroup:new{
                        HorizontalSpan:new{ width = wleft_width },
                        HorizontalSpan:new{ width = wmain_left_padding },
                        wmain
                }
            else
                -- pad main widget on the left
                wmain = HorizontalGroup:new{
                        HorizontalSpan:new{ width = wmain_left_padding },
                        wmain
                }
            end
            -- add padded main widget
            table.insert(widget, LeftContainer:new{
                    dimen = dimen:copy(),
                    wmain
                })
            -- add right widget
            if wright then
                table.insert(widget, RightContainer:new{
                    dimen = dimen:copy(),
                    HorizontalGroup:new{
                        wright,
                        HorizontalSpan:new{ width = wright_right_padding },
                    },
                })
            end

        else -- bookinfo not found
            if self.init_done then
                -- Non-initial update(), but our widget is still not found:
                -- it does not need to change, so avoid remaking the same widget
                return
            end
            -- If we're in no image mode, don't save images in DB : people
            -- who don't care about images will have a smaller DB, but
            -- a new extraction will have to be made when one switch to image mode
            if self.do_cover_image then
                -- Not in db, we're going to fetch some cover
                self.cover_specs = cover_specs
            end
            --
            if self.do_hint_opened and DocSettings:hasSidecarFile(self.filepath) then
                self.been_opened = true
            end
            -- No right widget by default, except in History
            local wright
            local wright_width = 0
            local wright_right_padding = 0
            if self.mandatory then
                -- Currently only provided by History, giving the last time read.
                -- If we have it, we need to build a more complex widget with
                -- this date on the right
                local fileinfo_str = self.mandatory
                local fontsize_info = _fontSize(14, 18)
                local wfileinfo = TextWidget:new{
                    text = fileinfo_str,
                    face = Font:getFace("cfont", fontsize_info),
                    fgcolor = fgcolor,
                }
                local wpageinfo = TextWidget:new{ -- Empty but needed for similar positioning
                    text = "",
                    face = Font:getFace("cfont", fontsize_info),
                }
                wright_width = wfileinfo:getSize().w
                wright = CenterContainer:new{
                    dimen = Geom:new{ w = wright_width, h = dimen.h },
                    VerticalGroup:new{
                        align = "right",
                        VerticalSpan:new{ width = Screen:scaleBySize(2) },
                        wfileinfo,
                        wpageinfo,
                    }
                }
                wright_right_padding = Screen:scaleBySize(10)
            end
            -- A real simple widget, nothing fancy
            local hint = "…" -- display hint it's being loaded
            if self.file_deleted then -- unless file was deleted (can happen with History)
                hint = " " .. _("(deleted)")
            end
            local text = BD.filename(self.text)
            local text_widget
            local fontsize_no_bookinfo = _fontSize(18, 22)
            repeat
                if text_widget then
                    text_widget:free(true)
                end
                text_widget = TextBoxWidget:new{
                    text = text .. hint,
                    face = Font:getFace("cfont", fontsize_no_bookinfo),
                    width = dimen.w - 2 * Screen:scaleBySize(10) - wright_width - wright_right_padding,
                    alignment = "left",
                    fgcolor = fgcolor,
                }
                -- reduce font size for next loop, in case text widget is too large to fit into ListMenuItem
                fontsize_no_bookinfo = fontsize_no_bookinfo - fontsize_dec_step
            until text_widget:getSize().h <= dimen.h
            widget = LeftContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                    text_widget
                },
            }
            if wright then -- last read date, in History, even for deleted files
                widget = OverlapGroup:new{
                    dimen = dimen:copy(),
                    widget,
                    RightContainer:new{
                        dimen = dimen:copy(),
                        HorizontalGroup:new{
                            wright,
                            HorizontalSpan:new{ width = wright_right_padding },
                        },
                    },
                }
            end
        end
    end

    -- Fill container with our widget
    if self._underline_container[1] then
        -- There is a previous one, that we need to free()
        local previous_widget = self._underline_container[1]
        previous_widget:free()
    end
    -- Add some pad at top to balance with hidden underline line at bottom
    self._underline_container[1] = VerticalGroup:new{
        VerticalSpan:new{ width = self.underline_h },
        widget
    }
end

function ListMenuItem:paintTo(bb, x, y)
    -- We used to get non-integer x or y that would cause some mess with image
    -- inside FrameContainer were image would be drawn on top of the top border...
    -- Fixed by having TextWidget:updateSize() math.ceil()'ing its length and height
    -- But let us know if that happens again
    if x ~= math.floor(x) or y ~= math.floor(y) then
        logger.err("ListMenuItem:paintTo() got non-integer x/y :", x, y)
    end

    -- Original painting
    InputContainer.paintTo(self, bb, x, y)

    -- to which we paint over the shortcut icon
    if self.shortcut_icon then
        -- align it on bottom left corner of sub-widget
        local target = self[1][1][2]
        local ix
        if BD.mirroredUILayout() then
            ix = target.dimen.w - self.shortcut_icon.dimen.w
        else
            ix = 0
        end
        local iy = target.dimen.h - self.shortcut_icon.dimen.h
        self.shortcut_icon:paintTo(bb, x+ix, y+iy)
    end

    -- to which we paint over a dogear if needed
    if corner_mark and self.do_hint_opened and self.been_opened then
        -- align it on bottom right corner of widget
        local ix
        if BD.mirroredUILayout() then
            ix = 0
        else
            ix = self.width - corner_mark:getSize().w
        end
        local iy = self.height - corner_mark:getSize().h
        corner_mark:paintTo(bb, x+ix, y+iy)
    end

    -- to which we paint a small indicator if this book has a description
    if self.has_description and not BookInfoManager:getSetting("no_hint_description") then
        local target =  self[1][1][2]
        local d_w = Screen:scaleBySize(3)
        local d_h = math.ceil(target.dimen.h / 4)
        if self.do_cover_image and target[1][1][1] then
            -- it has an image, align it on image's framecontainer's right border
            target = target[1][1]
            local ix
            if BD.mirroredUILayout() then
                ix = target.dimen.x - d_w + 1
            else
                ix = target.dimen.x + target.dimen.w - 1
            end
            bb:paintBorder(ix, target.dimen.y, d_w, d_h, 1)
        else
            -- no image, align it to the left border
            local ix
            if BD.mirroredUILayout() then
                ix = target.dimen.x + target.dimen.w - d_w
            else
                ix = x
            end
            bb:paintBorder(ix, y, d_w, d_h, 1)
        end
    end
end

-- As done in MenuItem
function ListMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function ListMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    return true
end

-- The transient color inversions done in MenuItem:onTapSelect
-- and MenuItem:onHoldSelect are ugly when done on an image,
-- so let's not do it
-- Also, no need for 2nd arg 'pos' (only used in readertoc.lua)
function ListMenuItem:onTapSelect(arg)
    self.menu:onMenuSelect(self.entry)
    return true
end

function ListMenuItem:onHoldSelect(arg, ges)
    self.menu:onMenuHold(self.entry)
    return true
end


-- Simple holder of methods that will replace those
-- in the real Menu class or instance
local ListMenu = {}

function ListMenu:_recalculateDimen()
    self.portrait_mode = Screen:getWidth() <= Screen:getHeight()
    -- Find out available height from other UI elements made in Menu
    self.others_height = 0
    if self.title_bar then -- Menu:init() has been done
        if not self.is_borderless then
            self.others_height = self.others_height + 2
        end
        if not self.no_title then
            self.others_height = self.others_height + self.title_bar.dimen.h
        end
        if self.page_info then
            self.others_height = self.others_height + self.page_info:getSize().h
        end
    else
        -- Menu:init() not yet done: other elements used to calculate self.others_heights
        -- are not yet defined, so next calculations will be wrong, and we may get
        -- a self.perpage higher than it should be: Menu:init() will set a wrong self.page.
        -- We'll have to update it, if we want FileManager to get back to the original page.
        self.page_recalc_needed_next_time = true
        -- Also remember original position (and focused_path), which will be changed by
        -- Menu/FileChooser to a probably wrong value
        self.itemnum_orig = self.path_items[self.path]
        self.focused_path_orig = self.focused_path
    end
    local available_height = self.inner_dimen.h - self.others_height - Size.line.thin

    if self.files_per_page == nil then -- first drawing
        -- Default perpage is computed from a base of 64px per ListMenuItem,
        -- which gives 10 items on kobo glo hd.
        self.files_per_page = math.floor(available_height / scale_by_size / 64)
        BookInfoManager:saveSetting("files_per_page", self.files_per_page)
    end
    self.perpage = self.files_per_page
    if not self.portrait_mode then
        -- When in landscape mode, adjust perpage so items get a chance
        -- to have about the same height as when in portrait mode.
        -- This computation is not strictly correct, as "others_height" would
        -- have a different value in portrait mode. But let's go with that.
        local portrait_available_height = Screen:getWidth() - self.others_height - Size.line.thin
        local portrait_item_height = math.floor(portrait_available_height / self.perpage) - Size.line.thin
        self.perpage = Math.round(available_height / portrait_item_height)
    end

    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end

    -- menu item height based on number of items per page
    -- add space for the separator
    self.item_height = math.floor(available_height / self.perpage) - Size.line.thin
    self.item_width = self.inner_dimen.w
    self.item_dimen = Geom:new{
        x = 0, y = 0,
        w = self.item_width,
        h = self.item_height
    }

    if self.page_recalc_needed then
        -- self.page has probably been set to a wrong value, we recalculate
        -- it here as done in Menu:init() or Menu:switchItemTable()
        if #self.item_table > 0 then
            self.page = math.ceil((self.itemnum_orig or 1) / self.perpage)
        end
        if self.focused_path_orig then
            for num, item in ipairs(self.item_table) do
                if item.path == self.focused_path_orig then
                    self.page = math.floor((num-1) / self.perpage) + 1
                    break
                end
            end
        end
        if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end
        self.page_recalc_needed = nil
        self.itemnum_orig = nil
        self.focused_path_orig = nil
    end
    if self.page_recalc_needed_next_time then
        self.page_recalc_needed = true
        self.page_recalc_needed_next_time = nil
    end
end

function ListMenu:_updateItemsBuildUI()
    -- Build our list
    local line_widget = LineWidget:new{
        dimen = Geom:new{ w = self.width or self.screen_w, h = Size.line.thin },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
    table.insert(self.item_group, line_widget)
    local idx_offset = (self.page - 1) * self.perpage
    local select_number
    for idx = 1, self.perpage do
        local index = idx_offset + idx
        local entry = self.item_table[index]
        if entry == nil then break end
        entry.idx = index
        if index == self.itemnumber then -- focused item
            select_number = idx
        end
        -- Keyboard shortcuts, as done in Menu
        local item_shortcut, shortcut_style
        if self.is_enable_shortcut then
            item_shortcut = self.item_shortcuts[idx]
            shortcut_style = (idx < 11 or idx > 20) and "square" or "grey_square"
        end

        local item_tmp = ListMenuItem:new{
                height = self.item_height,
                width = self.item_width,
                entry = entry,
                text = getMenuText(entry),
                show_parent = self.show_parent,
                mandatory = entry.mandatory,
                dimen = self.item_dimen:copy(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                menu = self,
                do_cover_image = self._do_cover_images,
                do_hint_opened = self._do_hint_opened,
                do_filename_only = self._do_filename_only,
            }
        table.insert(self.item_group, item_tmp)
        table.insert(self.item_group, line_widget)

        -- this is for focus manager
        table.insert(self.layout, {item_tmp})

        if not item_tmp.bookinfo_found and not item_tmp.is_directory and not item_tmp.file_deleted then
            -- Register this item for update
            table.insert(self.items_to_update, item_tmp)
        end

    end
    return select_number
end

return ListMenu
