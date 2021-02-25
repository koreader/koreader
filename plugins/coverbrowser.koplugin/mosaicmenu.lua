local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
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
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template
local getMenuText = require("ui/widget/menu").getMenuText

local BookInfoManager = require("bookinfomanager")

-- Here is the specific UI implementation for "mosaic" display modes
-- (see covermenu.lua for the generic code)

-- We will show a rotated dogear at bottom right corner of cover widget for
-- opened files (the dogear will make it look like a "used book")
-- The ImageWidget Will be created when we know the available height (and
-- recreated if height changes)
local corner_mark_size = -1
local corner_mark

-- ItemShortCutIcon (for keyboard navigation) is private to menu.lua and can't be accessed,
-- so we need to redefine it
local ItemShortCutIcon = WidgetContainer:new{
    dimen = Geom:new{ w = Screen:scaleBySize(22), h = Screen:scaleBySize(22) },
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
        dimen = self.dimen,
        CenterContainer:new{
            dimen = self.dimen,
            TextWidget:new{
                text = self.key,
                face = sc_face,
            },
        },
    }
end


-- We may find a better algorithm, or just a set of
-- nice looking combinations of 3 sizes to iterate thru
-- The rendering of the TextBoxWidget we're doing below
-- with decreasing font sizes till it fits is quite expensive.

local FakeCover = FrameContainer:new{
    width = nil,
    height = nil,
    margin = 0,
    padding = 0,
    bordersize = Size.border.thin,
    dim = nil,
    -- Provided filename, title and authors should not be BD wrapped
    filename = nil,
    file_deleted = nil,
    title = nil,
    authors = nil,
    -- The *_add should be provided BD wrapped if needed
    filename_add = nil,
    title_add = nil,
    authors_add = nil,
    book_lang = nil,
    -- these font sizes will be scaleBySize'd by Font:getFace()
    authors_font_max = 20,
    authors_font_min = 6,
    title_font_max = 24,
    title_font_min = 10,
    filename_font_max = 10,
    filename_font_min = 8,
    top_pad = Size.padding.default,
    bottom_pad = Size.padding.default,
    sizedec_step = Screen:scaleBySize(2), -- speeds up a bit if we don't do all font sizes
    initial_sizedec = 0,
}

function FakeCover:init()
    -- BookInfoManager:extractBookInfo() made sure
    -- to save as nil (NULL) metadata that were an empty string
    local authors = self.authors
    local title = self.title
    local filename = self.filename
    -- (some engines may have already given filename (without extension) as title)
    local bd_wrap_title_as_filename = false
    if not title then -- use filename as title (big and centered)
        title = filename
        filename = nil
        if not self.title_add and self.filename_add then
            -- filename_add ("…" or "(deleted)") always comes without any title_add
            self.title_add = self.filename_add
            self.filename_add = nil
        end
        bd_wrap_title_as_filename = true
    end
    if filename then
        filename = BD.filename(filename)
    end
    -- If no authors, and title is filename without extension, it was
    -- probably made by an engine, and we can consider it a filename, and
    -- act according to common usage in naming files.
    if not authors and title and self.filename and self.filename:sub(1,title:len()) == title then
        bd_wrap_title_as_filename = true
        -- Replace a hyphen surrounded by spaces (which most probably was
        -- used to separate Authors/Title/Serie/Year/Categorie in the
        -- filename with a \n
        title = title:gsub(" %- ", "\n")
        -- Same with |
        title = title:gsub("|", "\n")
        -- Also replace underscores with spaces
        title = title:gsub("_", " ")
        -- Some filenames may also use dots as separators, but dots
        -- can also have some meaning, so we can't just remove them.
        -- But at least, make dots breakable (they wouldn't be if not
        -- followed by a space), by adding to them a zero-width-space,
        -- so the dots stay on the right of their preceeding word.
        title = title:gsub("%.", ".\xE2\x80\x8B")
        -- Except for a last dot near end of title that might preceed
        -- a file extension: we'd rather want the dot and its suffix
        -- together on a last line: so, move the zero-width-space
        -- before it.
        title = title:gsub("%.\xE2\x80\x8B(%w%w?%w?%w?%w?)$", "\xE2\x80\x8B.%1")
        -- These substitutions will hopefully have no impact with the following BD wrapping
    end
    if title then
        title = bd_wrap_title_as_filename and BD.filename(title) or BD.auto(title)
    end
    -- If multiple authors (crengine separates them with \n), we
    -- can display them on multiple lines, but limit to 3, and
    -- append "et al." on a 4th line if there are more
    if authors and authors:find("\n") then
        authors = util.splitToArray(authors, "\n")
        for i=1, #authors do
            authors[i] = BD.auto(authors[i])
        end
        if #authors > 3 then
            authors = { authors[1], authors[2], T(_("%1 et al."), authors[3]) }
        end
        authors = table.concat(authors, "\n")
    elseif authors then
        authors = BD.auto(authors)
    end
    -- Add any _add, which must be already BD wrapped if needed
    if self.filename_add then
        filename = (filename and filename or "") .. self.filename_add
    end
    if self.title_add then
        title = (title and title or "") .. self.title_add
    end
    if self.authors_add then
        authors = (authors and authors or "") .. self.authors_add
    end

    -- We build the VerticalGroup widget with decreasing font sizes till
    -- the widget fits into available height
    local width = self.width - 2*(self.bordersize + self.margin + self.padding)
    local height = self.height - 2*(self.bordersize + self.margin + self.padding)
    local text_width = 7/8 * width -- make width of text smaller to have some padding
    local inter_pad
    local sizedec = self.initial_sizedec
    local authors_wg, title_wg, filename_wg
    local loop2 = false -- we may do a second pass with modifier title and authors strings
    while true do
        -- Free previously made widgets to avoid memory leaks
        if authors_wg then
            authors_wg:free()
            authors_wg = nil
        end
        if title_wg then
            title_wg:free()
            title_wg = nil
        end
        if filename_wg then
            filename_wg:free()
            filename_wg = nil
        end
        -- Build new widgets
        local texts_height = 0
        if authors then
            authors_wg = TextBoxWidget:new{
                text = authors,
                lang = self.book_lang,
                face = Font:getFace("cfont", math.max(self.authors_font_max - sizedec, self.authors_font_min)),
                width = text_width,
                alignment = "center",
            }
            texts_height = texts_height + authors_wg:getSize().h
        end
        if title then
            title_wg = TextBoxWidget:new{
                text = title,
                lang = self.book_lang,
                face = Font:getFace("cfont", math.max(self.title_font_max - sizedec, self.title_font_min)),
                width = text_width,
                alignment = "center",
            }
            texts_height = texts_height + title_wg:getSize().h
        end
        if filename then
            filename_wg = TextBoxWidget:new{
                text = filename,
                lang = self.book_lang, -- might as well use it for filename
                face = Font:getFace("cfont", math.max(self.filename_font_max - sizedec, self.filename_font_min)),
                width = text_width,
                alignment = "center",
            }
            texts_height = texts_height + filename_wg:getSize().h
        end
        local free_height = height - texts_height
        if authors then
            free_height = free_height - self.top_pad
        end
        if filename then
            free_height = free_height - self.bottom_pad
        end
        inter_pad = math.floor(free_height / 2)

        local textboxes_ok = true
        if (authors_wg and authors_wg.has_split_inside_word) or (title_wg and title_wg.has_split_inside_word) then
            -- We may get a nicer cover at next lower font size
            textboxes_ok = false
        end

        if textboxes_ok and free_height > 0.2 * height then -- enough free space to not look constrained
            break
        end
        -- (We may store the first widgets matching free space requirements but
        -- not textboxes_ok, so that if we never ever get textboxes_ok candidate,
        -- we can use them instead of the super-small strings-modified we'll have
        -- at the end that are worse than the firsts)

        sizedec = sizedec + self.sizedec_step
        if sizedec > 20 then -- break out of loop when too small
            -- but try a 2nd loop with some cleanup to strings (for filenames
            -- with no space but hyphen or underscore instead)
            if not loop2  then
                loop2 = true
                sizedec = self.initial_sizedec -- restart from initial big size
                if G_reader_settings:nilOrTrue("use_xtext") then
                    -- With Unicode/libunibreak, a break after a hyphen is allowed,
                    -- but not around underscores and dots without any space around.
                    -- So, append a zero-width-space to allow text wrap after them.
                    if title then
                        title = title:gsub("_", "_\xE2\x80\x8B"):gsub("%.", ".\xE2\x80\x8B")
                    end
                    if authors then
                        authors = authors:gsub("_", "_\xE2\x80\x8B"):gsub("%.", ".\xE2\x80\x8B")
                    end
                else
                    -- Replace underscores and hyphens with spaces, to allow text wrap there.
                    if title then
                        title = title:gsub("-", " "):gsub("_", " ")
                    end
                    if authors then
                        authors = authors:gsub("-", " "):gsub("_", " ")
                    end
                end
            else -- 2nd loop done, no luck, give up
                break
            end
        end
    end

    local vgroup = VerticalGroup:new{}
    if authors then
        table.insert(vgroup, VerticalSpan:new{ width = self.top_pad })
        table.insert(vgroup, authors_wg)
    end
    table.insert(vgroup, VerticalSpan:new{ width = inter_pad })
    if title then
        table.insert(vgroup, title_wg)
    end
    table.insert(vgroup, VerticalSpan:new{ width = inter_pad })
    if filename then
        table.insert(vgroup, filename_wg)
        table.insert(vgroup, VerticalSpan:new{ width = self.bottom_pad })
    end

    if self.file_deleted then
        self.dim = true
        self.color = Blitbuffer.COLOR_DARK_GRAY
    end

    -- As we are a FrameContainer, a border will be painted around self[1]
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = width,
            h = height,
        },
        vgroup,
    }
end


-- Based on menu.lua's MenuItem
local MosaicMenuItem = InputContainer:new{
    entry = {},
    text = nil,
    show_parent = nil,
    detail = nil,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    _underline_container = nil,
    do_cover_image = false,
    do_hint_opened = false,
    been_opened = false,
    init_done = false,
    bookinfo_found = false,
    cover_specs = nil,
    has_description = false,
}

function MosaicMenuItem:init()
    -- filepath may be provided as 'file' (history) or 'path' (filechooser)
    -- store it as attribute so we can use it elsewhere
    self.filepath = self.entry.file or self.entry.path

    -- As done in MenuItem
    -- Squared letter for keyboard navigation
    if self.shortcut then
        local shortcut_icon_dimen = Geom:new()
        shortcut_icon_dimen.w = math.floor(self.dimen.h*1/5)
        shortcut_icon_dimen.h = shortcut_icon_dimen.w
        -- To keep a simpler widget structure, this shortcut icon will not
        -- be part of it, but will be painted over the widget in our paintTo
        self.shortcut_icon = ItemShortCutIcon:new{
            dimen = shortcut_icon_dimen,
            key = self.shortcut,
            style = self.shortcut_style,
        }
    end
    self.detail = self.text

    -- we need this table per-instance, so we declare it here
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
                doc = "Select Menu Item",
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
                doc = "Hold Menu Item",
            },
        }
    end

    -- We now build the minimal widget container that won't change after udpate()

    -- As done in MenuItem
    -- for compatibility with keyboard navigation
    -- (which does not seem to work well when multiple pages,
    -- even with classic menu)
    self.underline_h = 1 -- smaller than default (3), don't waste space
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

function MosaicMenuItem:update()
    -- We will be a disctinctive widget whether we are a directory,
    -- a known file with image / without image, or a not yet known file
    local widget

    local dimen = Geom:new{
        w = self.width,
        h = self.height - self.underline_h
    }

    -- We'll draw a border around cover images, it may not be
    -- needed with some covers, but it's nicer when cover is
    -- a pure white background (like rendered text page)
    local border_size = Size.border.thin
    local max_img_w = dimen.w - 2*border_size
    local max_img_h = dimen.h - 2*border_size
    local cover_specs = {
        sizetag = "M",
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

    local file_mode = lfs.attributes(self.filepath, "mode")
    if file_mode == "directory" then
        self.is_directory = true
        -- Directory : rounded corners
        local margin = Screen:scaleBySize(5) -- make directories less wide
        local padding = Screen:scaleBySize(5)
        border_size = Size.border.thick -- make directories' borders larger
        local dimen_in = Geom:new{
            w = dimen.w - (margin + padding + border_size)*2,
            h = dimen.h - (margin + padding + border_size)*2
        }
        local text = self.text
        if text:match('/$') then -- remove /, more readable
            text = text:sub(1, -2)
        end
        text = BD.directory(text)
        local nbitems = TextBoxWidget:new{
            text = self.mandatory,
            face = Font:getFace("infont", 15),
            width = dimen_in.w,
            alignment = "center",
        }
        -- The directory name will be centered, with nbitems at bottom.
        -- We could use 2*nbitems:getSize().h to keep that centering,
        -- but using 3* will avoid getting the directory name stuck
        -- to nbitems.
        local available_height = dimen_in.h - 3 * nbitems:getSize().h
        local dir_font_size = 20
        local directory
        while true do
            if directory then
                directory:free()
            end
            directory = TextBoxWidget:new{
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen_in.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then
                break
            end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then -- don't go too low
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end
        widget = FrameContainer:new{
            width = dimen.w,
            height = dimen.h,
            margin = margin,
            padding = padding,
            bordersize = border_size,
            radius = Screen:scaleBySize(10),
            OverlapGroup:new{
                dimen = dimen_in,
                CenterContainer:new{ dimen=dimen_in, directory},
                BottomContainer:new{ dimen=dimen_in, nbitems},
            },
        }
    else
        if file_mode ~= "file" then
            self.file_deleted = true
        end
        -- File : various appearances

        if self.do_hint_opened and DocSettings:hasSidecarFile(self.filepath) then
            self.been_opened = true
        end

        local bookinfo = BookInfoManager:getBookInfo(self.filepath, self.do_cover_image)
        if bookinfo and self.do_cover_image and not bookinfo.ignore_cover then
            if bookinfo.cover_fetched then
                if bookinfo.has_cover and bookinfo.cover_sizetag ~= "M" then
                    -- there is a cover, but it's a small one (made by ListMenuItem),
                    -- and it would be ugly if scaled up to MosaicMenuItem size:
                    -- do as if not found to force a new extraction with our size
                    if bookinfo.cover_bb then
                        bookinfo.cover_bb:free()
                    end
                    bookinfo = nil
                    -- Note: with the current size differences between FileManager
                    -- and the History windows, we'll get lower max_img_* in History.
                    -- So, when one get Items first generated by the other, it will
                    -- have to do some scaling. Hopefully, people most probably
                    -- browse a lot more files than have them in history, so
                    -- it's most probably History that will have to do some scaling.
                end
                -- if not has_cover, book has no cover, no need to try again
            else
                -- cover was not fetched previously, do as if not found
                -- to force a new extraction
                bookinfo = nil
            end
        end

        if bookinfo then -- This book is known
            local cover_bb_used = false
            self.bookinfo_found = true
            -- For wikipedia saved as epub, we made a cover from the 1st pic of the page,
            -- which may not say much about the book. So, here, pretend we don't have
            -- a cover
            if bookinfo.authors and bookinfo.authors:match("^Wikipedia ") then
                bookinfo.has_cover = nil
            end
            if self.do_cover_image and bookinfo.has_cover and not bookinfo.ignore_cover then
                cover_bb_used = true
                -- Let ImageWidget do the scaling and give us a bb that fit
                local scale_factor = math.min(max_img_w / bookinfo.cover_w, max_img_h / bookinfo.cover_h)
                local image= ImageWidget:new{
                    image = bookinfo.cover_bb,
                    scale_factor = scale_factor,
                }
                image:_render()
                local image_size = image:getSize()
                widget = CenterContainer:new{
                    dimen = dimen,
                    FrameContainer:new{
                        width = image_size.w + 2*border_size,
                        height = image_size.h + 2*border_size,
                        margin = 0,
                        padding = 0,
                        bordersize = border_size,
                        dim = self.file_deleted,
                        color = self.file_deleted and Blitbuffer.COLOR_DARK_GRAY or nil,
                        image,
                    }
                }
                -- Let menu know it has some item with images
                self.menu._has_cover_images = true
                self._has_cover_image = true
            else
                -- add Series metadata if requested
                local series_mode = BookInfoManager:getSetting("series_mode")
                local title_add, authors_add
                if bookinfo.series then
                    if bookinfo.series_index then
                        bookinfo.series = BD.auto(bookinfo.series .. " #" .. bookinfo.series_index)
                    else
                        bookinfo.series = BD.auto(bookinfo.series)
                    end
                    if series_mode == "append_series_to_title" then
                        if bookinfo.title then
                            title_add = " - " .. bookinfo.series
                        else
                            title_add = bookinfo.series
                        end
                    end
                    if not bookinfo.authors then
                        if series_mode == "append_series_to_authors" or series_mode == "series_in_separate_line" then
                            authors_add = bookinfo.series
                        end
                    else
                        if series_mode == "append_series_to_authors" then
                            authors_add = " - " .. bookinfo.series
                        elseif series_mode == "series_in_separate_line" then
                            authors_add = "\n \n" .. bookinfo.series
                        end
                    end
                end
                widget = CenterContainer:new{
                    dimen = dimen,
                    FakeCover:new{
                        -- reduced width to make it look less squared, more like a book
                        width = math.floor(dimen.w * 7/8),
                        height = dimen.h,
                        bordersize = border_size,
                        filename = self.text,
                        title = not bookinfo.ignore_meta and bookinfo.title,
                        authors = not bookinfo.ignore_meta and bookinfo.authors,
                        title_add = not bookinfo.ignore_meta and title_add,
                        authors_add = not bookinfo.ignore_meta and authors_add,
                        book_lang = not bookinfo.ignore_meta and bookinfo.language,
                        file_deleted = self.file_deleted,
                    }
                }
            end
            -- In case we got a blitbuffer and didnt use it (ignore_cover, wikipedia), free it
            if bookinfo.cover_bb and not cover_bb_used then
                bookinfo.cover_bb:free()
            end
            -- So we can draw an indicator if this book has a description
            if bookinfo.description then
                self.has_description = true
            end

        else -- bookinfo not found
            if self.init_done then
                -- Non-initial update(), but our widget is still not found:
                -- it does not need to change, so avoid making the same FakeCover
                return
            end
            -- If we're in no image mode, don't save images in DB : people
            -- who don't care about images will have a smaller DB, but
            -- a new extraction will have to be made when one switch to image mode
            if self.do_cover_image then
                -- Not in db, we're going to fetch some cover
                self.cover_specs = cover_specs
            end
            -- Same as real FakeCover, but let it be squared (like a file)
            local hint = "…" -- display hint it's being loaded
            if self.file_deleted then -- unless file was deleted (can happen with History)
                hint = _("(deleted)")
            end
            widget = CenterContainer:new{
                dimen = dimen,
                FakeCover:new{
                    width = dimen.w,
                    height = dimen.h,
                    bordersize = border_size,
                    filename = self.text,
                    filename_add = "\n" .. hint,
                    initial_sizedec = 4, -- start with a smaller font when filenames only
                    file_deleted = self.file_deleted,
                }
            }
        end
    end

    -- Fill container with our widget
    if self._underline_container[1] then
        -- There is a previous one, that we need to free()
        local previous_widget = self._underline_container[1]
        previous_widget:free()
    end
    self._underline_container[1] = widget
end

function MosaicMenuItem:paintTo(bb, x, y)
    -- We used to get non-integer x or y that would cause some mess with image
    -- inside FrameContainer were image would be drawn on top of the top border...
    -- Fixed by having TextWidget:updateSize() math.ceil()'ing its length and height
    -- But let us know if that happens again
    if x ~= math.floor(x) or y ~= math.floor(y) then
        logger.err("MosaicMenuItem:paintTo() got non-integer x/y :", x, y)
    end

    -- Original painting
    InputContainer.paintTo(self, bb, x, y)

    -- to which we paint over the shortcut icon
    if self.shortcut_icon then
        -- align it on bottom left corner of widget
        local target = self
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
        -- align it on bottom right corner of sub-widget
        local target =  self[1][1][1]
        local ix
        if BD.mirroredUILayout() then
            ix = math.floor((self.width - target.dimen.w)/2)
        else
            ix = self.width - math.ceil((self.width - target.dimen.w)/2) - corner_mark:getSize().w
        end
        local iy = self.height - math.ceil((self.height - target.dimen.h)/2) - corner_mark:getSize().h
        -- math.ceil() makes it looks better than math.floor()
        corner_mark:paintTo(bb, x+ix, y+iy)
    end

    -- to which we paint a small indicator if this book has a description
    if self.has_description and not BookInfoManager:getSetting("no_hint_description") then
        -- On book's right (for similarity to ListMenuItem)
        local target =  self[1][1][1]
        local d_w = Screen:scaleBySize(3)
        local d_h = math.ceil(target.dimen.h / 8)
        -- Paint it directly relative to target.dimen.x/y which has been computed at this point
        local ix
        if BD.mirroredUILayout() then
            ix = - d_w + 1
            -- Set alternate dimen to be marked as dirty to include this description in refresh
            local x_overflow_left = x - target.dimen.x+ix -- positive if overflow
            if x_overflow_left > 0 then
                self.refresh_dimen = self[1].dimen:copy()
                self.refresh_dimen.x = self.refresh_dimen.x - x_overflow_left
                self.refresh_dimen.w = self.refresh_dimen.w + x_overflow_left
            end
        else
            ix = target.dimen.w - 1
            -- Set alternate dimen to be marked as dirty to include this description in refresh
            local x_overflow_right = target.dimen.x+ix+d_w - x - self.dimen.w
            if x_overflow_right > 0 then
                self.refresh_dimen = self[1].dimen:copy()
                self.refresh_dimen.w = self.refresh_dimen.w + x_overflow_right
            end
        end
        local iy = 0
        bb:paintBorder(target.dimen.x+ix, target.dimen.y+iy, d_w, d_h, 1)

    end
end

-- As done in MenuItem
function MosaicMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function MosaicMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    return true
end

function MosaicMenuItem:onShowItemDetail()
    UIManager:show(InfoMessage:new{ text = self.detail, })
    return true
end

-- The transient color inversions done in MenuItem:onTapSelect
-- and MenuItem:onHoldSelect are ugly when done on an image,
-- so let's not do it
-- Also, no need for 2nd arg 'pos' (only used in readertoc.lua)
function MosaicMenuItem:onTapSelect(arg)
    self.menu:onMenuSelect(self.entry)
    return true
end

function MosaicMenuItem:onHoldSelect(arg, ges)
    self.menu:onMenuHold(self.entry)
    return true
end


-- Simple holder of methods that will replace those
-- in the real Menu class or instance
local MosaicMenu = {}

function MosaicMenu:_recalculateDimen()
    local portrait_mode = Screen:getWidth() <= Screen:getHeight()
    -- 3 x 3 grid by default if not initially provided (4 x 2 in landscape mode)
    if portrait_mode then
        self.nb_cols = self.nb_cols_portrait or 3
        self.nb_rows = self.nb_rows_portrait or 3
    else
        self.nb_cols = self.nb_cols_landscape or 4
        self.nb_rows = self.nb_rows_landscape or 2
    end
    self.perpage = self.nb_rows * self.nb_cols
    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end

    -- Find out available height from other UI elements made in Menu
    self.others_height = 0
    if self.title_bar then -- init() has been done
        if not self.is_borderless then
            self.others_height = self.others_height + 2
        end
        if not self.no_title then
            self.others_height = self.others_height + self.header_padding
            self.others_height = self.others_height + self.title_bar.dimen.h
        end
        if self.page_info then
            self.others_height = self.others_height + self.page_info:getSize().h
        end
    end

    -- Set our items target size
    self.item_margin = Screen:scaleBySize(10)
    self.item_height = math.floor((self.inner_dimen.h - self.others_height - (1+self.nb_rows)*self.item_margin) / self.nb_rows)
    self.item_width = math.floor((self.inner_dimen.w - (1+self.nb_cols)*self.item_margin) / self.nb_cols)
    self.item_dimen = Geom:new{
        w = self.item_width,
        h = self.item_height
    }

    -- Create or replace corner_mark if needed
    -- 1/12 (larger) or 1/16 (smaller) of cover looks allright
    local mark_size = math.floor(math.min(self.item_width, self.item_height) / 16)
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
end

function MosaicMenu:_updateItemsBuildUI()
    -- Build our grid
    local idx_offset = (self.page - 1) * self.perpage
    local cur_row = nil
    for idx = 1, self.perpage do
        local entry = self.item_table[idx_offset + idx]
        if entry == nil then break end

        if idx % self.nb_cols == 1 then -- new row
            table.insert(self.item_group, VerticalSpan:new{ width = self.item_margin })
            cur_row = HorizontalGroup:new{}
            -- Have items on the possibly non-fully filled last row aligned to the left
            local container = self._do_center_partial_rows and CenterContainer or LeftContainer
            table.insert(self.item_group, container:new{
                dimen = Geom:new{
                    w = self.inner_dimen.w,
                    h = self.item_height
                },
                cur_row
            })
            table.insert(cur_row, HorizontalSpan:new({ width = self.item_margin }))
        end

        -- Keyboard shortcuts, as done in Menu
        local item_shortcut = nil
        local shortcut_style = "square"
        if self.is_enable_shortcut then
            -- give different shortcut_style to keys in different
            -- lines of keyboard
            if idx >= 11 and idx <= 20 then
                shortcut_style = "grey_square"
            end
            item_shortcut = self.item_shortcuts[idx]
        end

        local item_tmp = MosaicMenuItem:new{
                height = self.item_height,
                width = self.item_width,
                entry = entry,
                text = getMenuText(entry),
                show_parent = self.show_parent,
                mandatory = entry.mandatory,
                dimen = self.item_dimen:new(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                menu = self,
                do_cover_image = self._do_cover_images,
                do_hint_opened = self._do_hint_opened,
            }
        table.insert(cur_row, item_tmp)
        table.insert(cur_row, HorizontalSpan:new({ width = self.item_margin }))

        -- this is for focus manager
        table.insert(self.layout, {item_tmp})

        if not item_tmp.bookinfo_found and not item_tmp.is_directory and not item_tmp.file_deleted then
            -- Register this item for update
            table.insert(self.items_to_update, item_tmp)
        end
    end
    table.insert(self.item_group, VerticalSpan:new{ width = self.item_margin }) -- bottom padding
end

return MosaicMenu
