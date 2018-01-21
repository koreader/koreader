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
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
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

local BookInfoManager = require("bookinfomanager")

-- Here is the specific UI implementation for "list" display modes
-- (see covermenu.lua for the generic code)

-- We will show a rotated dogear at bottom right corner of cover widget for
-- opened files (the dogear will make it look like a "used book")
local corner_mark = ImageWidget:new{
    file = "resources/icons/dogear.png",
    rotation_angle = 270
}

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
        background = Blitbuffer.gray(0.2)
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


-- Based on menu.lua's MenuItem
local ListMenuItem = InputContainer:new{
    entry = {},
    text = nil,
    show_parent = nil,
    detail = nil,
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
    -- filepath may be provided as 'file' (history) or 'path' (filechooser)
    -- store it as attribute so we can use it elsewhere
    self.filepath = self.entry.file or self.entry.path

    -- As done in MenuItem
    -- Squared letter for keyboard navigation
    if self.shortcut then
        local shortcut_icon_dimen = Geom:new()
        shortcut_icon_dimen.w = math.floor(self.dimen.h*2/5)
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
    if Device:hasKeys() then
        self.active_key_events = {
            Select = { {"Press"}, doc = "chose selected item" },
        }
    end

    -- We now build the minimal widget container that won't change after udpate()

    -- As done in MenuItem
    -- for compatibility with keyboard navigation
    -- (which does not seem to work well when multiple pages,
    -- even with classic menu)
    self.underline_h = 1 -- smaller than default (3) to not shift our vertical aligment
    self._underline_container = UnderlineContainer:new{
        vertical_align = "center",
        dimen = Geom:new{
            w = self.width,
            h = self.height
        },
        linesize = self.underline_h,
        padding = 0,
        -- widget : will be filled in self:update()
    }
    self[1] = self._underline_container

    -- Remaining part of initialization is done in update(), because we may
    -- have to do it more than once if item not found in db
    self:update()
    self.init_done = true
end

function ListMenuItem:update()
    -- We will be a disctinctive widget whether we are a directory,
    -- a known file with image / without image, or a not yet known file
    local widget

    -- we'll add a VerticalSpan of same size as underline container for balance
    local dimen = Geom:new{
        w = self.width,
        h = self.height - 2 * self.underline_h
    }

    local file_mode = lfs.attributes(self.filepath, "mode")
    if file_mode == "directory" then
        self.is_directory = true
        -- nb items on the right, directory name on the left
        local wright = TextWidget:new{
            text = self.mandatory,
            face = Font:getFace("infont", 15),
        }
        local wleft_width = dimen.w - wright:getSize().w
        local wleft = TextBoxWidget:new{
            text = self.text,
            face = Font:getFace("cfont", 20),
            width = wleft_width,
            alignment = "left",
            bold = true,
        }
        widget = OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                    wleft,
                }
            },
            RightContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    wright,
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                },
            },
        }
    else
        if file_mode ~= "file" then
            self.file_deleted = true
        end
        -- File
        local border_size = 1
        local max_img_w = dimen.h - 2*border_size -- width = height, squared
        local max_img_h = dimen.h - 2*border_size

        local bookinfo = BookInfoManager:getBookInfo(self.filepath, self.do_cover_image)
        if bookinfo and self.do_cover_image and not bookinfo.ignore_cover then
            if not bookinfo.cover_fetched then
                -- cover was not fetched previously, do as if not found
                -- to force a new extraction
                bookinfo = nil
            end
            -- If there's already a cover and it's a "M" size (MosaicMenuItem),
            -- we'll use it and scale it down (it may slow a bit rendering,
            -- but "M" size may be useful in another view (FileBrowser/History),
            -- so we don't replace it).
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
                    local scale_factor = math.min(max_img_w / bookinfo.cover_w, max_img_h / bookinfo.cover_h)
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
                else
                    -- empty element the size of an image
                    wleft = CenterContainer:new{
                        dimen = Geom:new{ w = wleft_width, h = wleft_height },
                        HorizontalSpan:new{ width = wleft_width },
                    }
                end
            end
            -- In case we got a blitbuffer and didnt use it (ignore_cover), free it
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
            local directory, filename = util.splitFilePathName(self.filepath) -- luacheck: no unused
            local filename_without_suffix, filetype = util.splitFileNameSuffix(filename)
            local fileinfo_str = filetype
            if self.mandatory then
                fileinfo_str = self.mandatory .. "  " .. fileinfo_str
            end
            -- Current page / pages are available or more accurate in .sdr/metadata.lua
            -- We use a cache (cleaned at end of this browsing session) to store
            -- page and percent read from sidecar files, to avoid re-parsing them
            -- when re-rendering a visited page
            if not self.menu.cover_info_cache then
                self.menu.cover_info_cache = {}
            end
            local pages_str = ""
            local percent_finished
            local pages = bookinfo.pages -- default to those in bookinfo db
            if DocSettings:hasSidecarFile(self.filepath) then
                self.been_opened = true
                if self.menu.cover_info_cache[self.filepath] then
                    pages, percent_finished = unpack(self.menu.cover_info_cache[self.filepath])
                else
                    local docinfo = DocSettings:open(self.filepath)
                    -- We can get nb of page in the new 'doc_pages' setting, or from the old 'stats.page'
                    if docinfo.data.doc_pages then
                        pages = docinfo.data.doc_pages
                    elseif docinfo.data.stats and docinfo.data.stats.pages then
                        if docinfo.data.stats.pages ~= 0 then -- crengine with statistics disabled stores 0
                            pages = docinfo.data.stats.pages
                        end
                    end
                    percent_finished = docinfo.data.percent_finished
                    self.menu.cover_info_cache[self.filepath] = {pages, percent_finished}
                end
            end
            if percent_finished then
                if pages then
                    pages_str = T(_("%1 % of %2 pages"), math.floor(100*percent_finished), pages)
                else
                    pages_str = string.format("%d %%", math.floor(100*percent_finished))
                end
            else
                if pages then
                    pages_str = T(_("%1 pages"), pages)
                end
            end

            -- Build the right widget

            local wfileinfo = TextWidget:new{
                text = fileinfo_str,
                face = Font:getFace("cfont", 14),
                fgcolor = self.file_deleted and Blitbuffer.COLOR_GREY or nil,
            }
            local wpageinfo = TextWidget:new{
                text = pages_str,
                face = Font:getFace("cfont", 14),
                fgcolor = self.file_deleted and Blitbuffer.COLOR_GREY or nil,
            }

            local wright_width = math.max(wfileinfo:getSize().w, wpageinfo:getSize().w)
            local wright_right_padding = Screen:scaleBySize(10)

            -- We just built two string to be put one on top of the other, and we want
            -- the combo centered. Given the nature of our strings (numbers,
            -- uppercase MB/KB on top text, number and lowercase "page" on bottom text),
            -- we get the annoying feeling it's not centered but shifted towards top.
            -- Let's add a small VerticalSpan at top to give a better visual
            -- feeling of centering.
            local wright = CenterContainer:new{
                dimen = Geom:new{ w = wright_width, h = dimen.h },
                VerticalGroup:new{
                    align = "right",
                    VerticalSpan:new{ width = Screen:scaleBySize(2) },
                    wfileinfo,
                    wpageinfo,
                }
            }


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
            local fontsize_title = 20
            local fontsize_authors = 18
            local wtitle, wauthors
            local title, authors
            -- whether to use or not title and authors
            if self.do_filename_only or bookinfo.ignore_meta then
                title = filename_without_suffix -- made out above
                authors = nil
            else
                title = bookinfo.title and bookinfo.title or filename_without_suffix
                authors = bookinfo.authors
                -- If multiple authors (crengine separates them with \n), we
                -- can display them on multiple lines, but limit to 2, and
                -- append "et al." to the 2nd if there are more
                if authors and authors:find("\n") then
                    authors = util.splitToArray(authors, "\n")
                    if #authors > 2 then
                        authors = { authors[1], T(_("%1 et al."), authors[2]) }
                    end
                    authors = table.concat(authors, "\n")
                end
            end
            -- add Series metadata if requested
            if bookinfo.series then
                if BookInfoManager:getSetting("append_series_to_title") then
                    -- Shorten calibre series decimal number (#4.0 => #4)
                    bookinfo.series = bookinfo.series:gsub("(#%d+)%.0$", "%1")
                    if title then
                        title = title .. " - " .. bookinfo.series
                    else
                        title = bookinfo.series
                    end
                end
                if BookInfoManager:getSetting("append_series_to_authors") then
                    bookinfo.series = bookinfo.series:gsub("(#%d+)%.0$", "%1")
                    if authors then
                        authors = authors .. " - " .. bookinfo.series
                    else
                        authors = bookinfo.series
                    end
                end
            end
            if bookinfo.unsupported then
                -- Let's show this fact in place of the anyway empty authors slot
                authors = T(_("(no book information: %1)"), bookinfo.unsupported)
            end
            -- Build title and authors texts with decreasing font size
            -- till it fits in the space available
            while true do
                -- Free previously made widgets to avoid memory leaks
                if wtitle then
                    wtitle:free()
                end
                if wauthors then
                    wauthors:free()
                    wauthors = nil
                end
                -- BookInfoManager:extractBookInfo() made sure
                -- to save as nil (NULL) metadata that were an empty string
                wtitle = TextBoxWidget:new{
                    text = title,
                    face = Font:getFace(fontname_title, fontsize_title),
                    width = wmain_width,
                    alignment = "left",
                    bold = true,
                    fgcolor = self.file_deleted and Blitbuffer.COLOR_GREY or nil,
                }
                local height = wtitle:getSize().h
                if authors then
                    wauthors = TextBoxWidget:new{
                        text = authors,
                        face = Font:getFace(fontname_authors, fontsize_authors),
                        width = wmain_width,
                        alignment = "left",
                        fgcolor = self.file_deleted and Blitbuffer.COLOR_GREY or nil,
                    }
                    height = height + wauthors:getSize().h
                end
                if height < dimen.h then -- we fit !
                    break
                end
                -- If we don't fit, decrease both font sizes
                fontsize_title = fontsize_title - 1
                fontsize_authors = fontsize_authors - 1
                -- Don't go too low, and get out of this loop
                if fontsize_title < 3 or fontsize_authors < 3 then
                    break
                end
            end

            local wmain = LeftContainer:new{
                dimen = dimen,
                VerticalGroup:new{
                    wtitle,
                    wauthors,
                }
            }

            -- Build the final widget
            widget = OverlapGroup:new{
                dimen = dimen,
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
                    dimen = dimen,
                    wmain
                })
            -- add right widget
            table.insert(widget, RightContainer:new{
                    dimen = dimen,
                    HorizontalGroup:new{
                        wright,
                        HorizontalSpan:new{ width = wright_right_padding },
                    },
                })

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
                self.cover_specs = {
                    sizetag = "s",
                    max_cover_w = max_img_w,
                    max_cover_h = max_img_h,
                }
            end
            --
            if self.do_hint_opened and DocSettings:hasSidecarFile(self.filepath) then
                self.been_opened = true
            end
            -- A real simple widget, nothing fancy
            local hint = "…" -- display hint it's being loaded
            if self.file_deleted then -- unless file was deleted (can happen with History)
                hint = " " .. _("(deleted)")
            end
            widget = LeftContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                    TextBoxWidget:new{
                        text = self.text .. hint,
                        face = Font:getFace("cfont", 18),
                        width = dimen.w - 2 * Screen:scaleBySize(10),
                        alignment = "left",
                        fgcolor = self.file_deleted and Blitbuffer.COLOR_GREY or nil,
                    }
                },
            }
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
        local ix = 0
        local iy = target.dimen.h - self.shortcut_icon.dimen.h
        self.shortcut_icon:paintTo(bb, x+ix, y+iy)
    end

    -- to which we paint over a dogear if needed
    if self.do_hint_opened and self.been_opened then
        -- align it on bottom right corner of widget
        local ix = self.width - corner_mark:getSize().w
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
            bb:paintBorder(target.dimen.x + target.dimen.w - 1, target.dimen.y, d_w, d_h, 1)
        else
            -- no image, align it to the left border
            bb:paintBorder(x, y, d_w, d_h, 1)
        end
    end
end

-- As done in MenuItem
function ListMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    self.key_events = self.active_key_events
    return true
end

function ListMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    self.key_events = {}
    return true
end

function ListMenuItem:onShowItemDetail()
    UIManager:show(InfoMessage:new{ text = self.detail, })
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
    self.dimen.w = self.width
    self.dimen.h = self.height or Screen:getHeight()

    -- Find out available height from other UI elements made in Menu
    self.others_height = 0
    if self.title_bar then -- Menu:init() has been done
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
    local available_height = self.dimen.h - self.others_height

    -- 64 hardcoded for now, gives 10 items both in filemanager
    -- and history on kobo glo hd
    local item_height_min = Screen:scaleBySize(64)
    self.perpage = math.floor(available_height / item_height_min)
    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- fix current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end

    local height_remaining = available_height - self.perpage * item_height_min
    height_remaining = height_remaining - (self.perpage+1) -- N+1 LineWidget separators
    self.item_height = item_height_min + math.floor(height_remaining / self.perpage)
    self.item_width = self.dimen.w
    self.item_dimen = Geom:new{
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
    table.insert(self.item_group, LineWidget:new{
                    dimen = Geom:new{ w = self.width, h = Size.line.thin },
                    background = Blitbuffer.COLOR_GREY,
                    style = "solid",
                })
    local idx_offset = (self.page - 1) * self.perpage
    for idx = 1, self.perpage do
        local entry = self.item_table[idx_offset + idx]
        if entry == nil then break end

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
            if item_shortcut == "Enter" then
                item_shortcut = "Ent"
            end
        end

        local item_tmp = ListMenuItem:new{
                height = self.item_height,
                width = self.item_width,
                entry = entry,
                text = util.getMenuText(entry),
                show_parent = self.show_parent,
                mandatory = entry.mandatory,
                dimen = self.item_dimen:new(),
                shortcut = item_shortcut,
                shortcut_style = shortcut_style,
                menu = self,
                do_cover_image = self._do_cover_images,
                do_hint_opened = self._do_hint_opened,
                do_filename_only = self._do_filename_only,
            }
        table.insert(self.item_group, item_tmp)
        table.insert(self.item_group, LineWidget:new{
                        dimen = Geom:new{ w = self.width, h = Size.line.thin },
                        background = Blitbuffer.COLOR_GREY,
                        style = "solid",
                    })

        -- this is for focus manager
        table.insert(self.layout, {item_tmp})

        if not item_tmp.bookinfo_found and not item_tmp.is_directory and not item_tmp.file_deleted then
            -- Register this item for update
            table.insert(self.items_to_update, item_tmp)
        end

    end
end

return ListMenu
