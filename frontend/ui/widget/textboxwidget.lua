--[[--
A TextWidget that handles long text wrapping

Example:

    local Foo = TextBoxWidget:new{
        face = Font:getFace("cfont", 25),
        text = 'We can show multiple lines.\nFoo.\nBar.',
        -- width = Screen:getWidth()*2/3,
    }
    UIManager:show(Foo)

]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local Math = require("optmath")
local logger = require("logger")
local util = require("util")
local Screen = require("device").screen

local TextBoxWidget = InputContainer:new{
    text = nil,
    editable = false, -- Editable flag for whether drawing the cursor or not.
    justified = false, -- Should text be justified (spaces widened to fill width)
    alignment = "left", -- or "center", "right"
    dialog = nil, -- parent dialog that will be set dirty
    face = nil,
    bold = nil,
    line_height = 0.3, -- in em
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = Screen:scaleBySize(400), -- in pixels
    height = nil, -- nil value indicates unscrollable text widget
    top_line_num = nil, -- original virtual_line_num to scroll to
    charpos = nil, -- idx of char to draw the cursor on its left (can exceed #charlist by 1)

    -- for internal use
    charlist = nil,   -- idx => char
    char_width = nil, -- char => width
    idx_pad = nil,     -- idx => pad for char at idx, if non zero
    vertical_string_list = nil,
    virtual_line_num = 1, -- index of the top displayed line
    line_height_px = nil, -- height of a line in px
    lines_per_page = nil, -- number of visible lines
    text_height = nil,    -- adjusted height to visible text (lines_per_page*line_height_px)
    cursor_line = nil, -- LineWidget to draw the vertical cursor.
    _bb = nil,

    -- We can provide a list of images: each image will be displayed on each
    -- scrolled page, in its top right corner (if more images than pages, remaining
    -- images will not be displayed at all - if more pages than images, remaining
    -- pages won't have any image).
    -- Each 'image' is a table with the following keys:
    --    width     width of small image displayed by us
    --    height    height of small image displayed by us
    --    bb        blitbuffer of small image, may be initially nil
    -- optional:
    --    hi_width  same as previous for a high-resolution version of the
    --    hi_height image, to be displayed by ImageViewer when Hold on
    --    hi_bb     blitbuffer of high-resolution image
    --    title     ImageViewer title
    --    caption   ImageViewer caption
    --
    --    load_bb_func  function called (with one arg: false to load 'bb', true to load 'hi_bb)
    --                  when bb or hi_bb is nil: its job is to load/build bb or hi_bb.
    --                  The page will refresh itself when load_bb_func returns.
    images = nil, -- list of such images
    line_num_to_image = nil, -- will be filled by self:_splitCharWidthList()
    image_padding_left = Screen:scaleBySize(10),
    image_padding_bottom = Screen:scaleBySize(3),
    image_alt_face = Font:getFace("xx_smallinfofont"),
    image_alt_fgcolor = Blitbuffer.COLOR_BLACK,
}

function TextBoxWidget:init()
    self.line_height_px = Math.round( (1 + self.line_height) * self.face.size )
    self.cursor_line = LineWidget:new{
        dimen = Geom:new{
            w = Size.line.medium,
            h = self.line_height_px,
        }
    }
    if self.height then
        -- luajit may segfault if we were provided with a negative height
        -- also ensure we display at least one line
        if self.height < self.line_height_px then
            self.height = self.line_height_px
        end
        -- if no self.height, these will be set just after self:_splitCharWidthList()
        self.lines_per_page = math.floor(self.height / self.line_height_px)
        self.text_height = self.lines_per_page * self.line_height_px
    end
    self:_evalCharWidthList()
    self:_splitCharWidthList()
    if self.charpos and self.charpos > #self.charlist+1 then
        self.charpos = #self.charlist+1
    end

    if self.height == nil then
        self.lines_per_page = #self.vertical_string_list
        self.text_height = self.lines_per_page * self.line_height_px
        self.virtual_line_num = 1
    else
        -- Show the previous displayed area in case of re-init (focus/unfocus)
        -- InputText may have re-created us, while providing the previous charlist,
        -- charpos and top_line_num.
        -- We need to show the line containing charpos, while trying to
        -- keep the previous top_line_num
        if self.editable and self.charpos then
            self:scrollViewToCharPos()
        end
    end
    self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    if self.editable then
        self:moveCursorToCharPos(self.charpos or 1)
    end
    self.dimen = Geom:new(self:getSize())
    if Device:isTouchDevice() then
        self.ges_events = {
            TapImage = {
                GestureRange:new{
                    ges = "tap",
                    range = function() return self.dimen end,
                },
            },
        }
    end
end

function TextBoxWidget:unfocus()
    self.editable = false
    self:free()
    self:init()
end

function TextBoxWidget:focus()
    self.editable = true
    self:free()
    self:init()
end

-- Split `self.text` into `self.charlist` and evaluate the width of each char in it.
function TextBoxWidget:_evalCharWidthList()
    -- if self.charlist is provided, use it directly
    if self.charlist == nil then
        self.charlist = util.splitToChars(self.text)
    end
    -- get width of each distinct char
    local char_width = {}
    for _, c in ipairs(self.charlist) do
        if not char_width[c] then
            char_width[c] = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, c, true, self.bold).x
        end
    end
    self.char_width = char_width
    self.idx_pad = {}
end

-- Split the text into logical lines to fit into the text box.
function TextBoxWidget:_splitCharWidthList()
    self.vertical_string_list = {}

    local idx = 1
    local size = #self.charlist
    local ln = 1
    local offset, end_offset, cur_line_width

    local image_num = 0
    local targeted_width = self.width
    local image_lines_remaining = 0
    while idx <= size do
        -- Every scrolled page, we want to add the next (if any) image at its top right
        -- (if not scrollable, we will display only the first image)
        -- We need to make shorter lines and leave room for the image
        if self.images and #self.images > 0 then
            if self.line_num_to_image == nil then
                self.line_num_to_image = {}
            end
            if (self.lines_per_page and ln % self.lines_per_page == 1) -- first line of a scrolled page
            or (self.lines_per_page == nil and ln == 1) then  -- first line if not scrollabled
                image_num = image_num + 1
                if image_num <= #self.images then
                    local image = self.images[image_num]
                    self.line_num_to_image[ln] = image
                    -- Resize image if really too big: bb will be cropped if already there,
                    -- but if loaded later with load_bb_func, load_bb_func may resize it
                    -- to the width and height we have updated here.
                    if image.width > self.width / 2 then
                        image.height = math.floor(image.height * (self.width / 2 / image.width))
                        image.width = math.floor(self.width / 2)
                    end
                    if image.height > self.height / 2 then
                        image.width = math.floor(image.width * (self.height / 2 / image.height))
                        image.height = math.floor(self.height / 2)
                    end
                    targeted_width = self.width - image.width - self.image_padding_left
                    image_lines_remaining = math.ceil((image.height + self.image_padding_bottom)/self.line_height_px)
                end
            end
            if image_lines_remaining > 0 then
                image_lines_remaining = image_lines_remaining - 1
            else
                targeted_width = self.width -- text can now use full width
            end
        end

        -- end_offset will be the idx of char at end of line
        offset = idx -- idx of char at start of line

        -- We append chars until the accumulated width exceeds `targeted_width`,
        -- or a newline occurs, or no more chars to consume.
        cur_line_width = 0
        local hard_newline = false
        while idx <= size do
            if self.charlist[idx] == "\n" then
                hard_newline = true
                break
            end
            cur_line_width = cur_line_width + self.char_width[self.charlist[idx]]
            if cur_line_width > targeted_width then break else idx = idx + 1 end
        end
        if cur_line_width <= targeted_width then -- a hard newline or end of string
            end_offset = idx - 1
        else
            -- Backtrack the string until the length fit into one line.
            -- We'll give next and prev chars to isSplittable() for a wiser decision
            local c = self.charlist[idx]
            local next_c = idx+1 <= size and self.charlist[idx+1] or false
            local prev_c = idx-1 >= 1 and self.charlist[idx-1] or false
            local adjusted_idx = idx
            local adjusted_width = cur_line_width
            while adjusted_idx > offset and not util.isSplittable(c, next_c, prev_c) do
                adjusted_width = adjusted_width - self.char_width[self.charlist[adjusted_idx]]
                adjusted_idx = adjusted_idx - 1
                next_c = c
                c = prev_c
                prev_c = adjusted_idx-1 >= 1 and self.charlist[adjusted_idx-1] or false
            end
            if adjusted_idx == offset or adjusted_idx == idx then
                -- either a very long english word occupying more than one line,
                -- or the excessive char is itself splittable:
                -- we let that excessive char for next line
                if adjusted_idx == offset then -- let the fact a long word was splitted be known
                    self.has_split_inside_word = true
                end
                end_offset = idx - 1
                cur_line_width = cur_line_width - self.char_width[self.charlist[idx]]
            elseif c == " " then
                -- we backtracked and we're below max width, but the last char
                -- is a space, we can ignore it
                end_offset = adjusted_idx - 1
                cur_line_width = adjusted_width - self.char_width[self.charlist[adjusted_idx]]
                idx = adjusted_idx + 1
            else
                -- we backtracked and we're below max width, we can leave the
                -- splittable char on this line
                end_offset = adjusted_idx
                cur_line_width = adjusted_width
                idx = adjusted_idx + 1
            end
            if self.justified then
                -- this line was splitted and can be justified
                -- we record in idx_pad the nb of pixels to add to each char
                -- to make the whole line justified. This also helps hold
                -- position accuracy.
                local fill_width = targeted_width - cur_line_width
                if fill_width > 0 then
                    local nbspaces = 0
                    for sidx = offset, end_offset do
                        if self.charlist[sidx] == " " then
                            nbspaces = nbspaces + 1
                        end
                    end
                    if nbspaces > 0 then
                        -- width added to all spaces
                        local space_add_w = math.floor(fill_width / nbspaces)
                        -- nb of spaces to which we'll add 1 more pixel
                        local space_add1_nb = fill_width - space_add_w * nbspaces
                        for cidx = offset, end_offset do
                            local pad
                            if self.charlist[cidx] == " " then
                                pad = space_add_w
                                if space_add1_nb > 0 then
                                    pad = pad + 1
                                    space_add1_nb = space_add1_nb - 1
                                end
                                if pad > 0 then self.idx_pad[cidx] = pad end
                            end
                        end
                    else
                        -- very long word, or CJK text with no space
                        -- pad first chars with 1 pixel
                        for cidx = offset, end_offset do
                            if fill_width > 0 then
                                self.idx_pad[cidx] = 1
                                fill_width = fill_width - 1
                            else
                                break
                            end
                        end
                    end
                end
            end
        end -- endif cur_line_width > targeted_width
        if cur_line_width < 0 then break end
        self.vertical_string_list[ln] = {
            offset = offset,
            end_offset = end_offset,
            width = cur_line_width,
        }
        if hard_newline then
            idx = idx + 1
            -- end_offset = nil means no text
            self.vertical_string_list[ln+1] = {offset = idx, end_offset = nil, width = 0}
        else
            -- If next char is a space, discard it so it does not become
            -- an ugly leading space on the next line
            if idx <= size and self.charlist[idx] == " " then
                idx = idx + 1
            end
        end
        ln = ln + 1
        -- Make sure `idx` point to the next char to be processed in the next loop.
    end
end

function TextBoxWidget:_getLineText(vertical_string)
    if not vertical_string.end_offset then return "" end
    return table.concat(self.charlist, "", vertical_string.offset, vertical_string.end_offset)
end

function TextBoxWidget:_getLinePads(vertical_string)
    if not vertical_string.end_offset then return end
    local pads = {}
    for idx = vertical_string.offset, vertical_string.end_offset do
        table.insert(pads, self.idx_pad[idx] or 0)
    end
    return pads
end

function TextBoxWidget:_renderText(start_row_idx, end_row_idx)
    local font_height = self.face.size
    if start_row_idx < 1 then start_row_idx = 1 end
    if end_row_idx > #self.vertical_string_list then end_row_idx = #self.vertical_string_list end
    local row_count = end_row_idx == 0 and 1 or end_row_idx - start_row_idx + 1
    -- We need a bb with the full height (even if we display only a few lines, we
    -- may have to draw an image bigger than these lines)
    local h = self.height or self.line_height_px * row_count
    if self._bb then self._bb:free() end
    local bbtype = nil
    if self.line_num_to_image and self.line_num_to_image[start_row_idx] then
        bbtype = Screen:isColorEnabled() and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
    end
    self._bb = Blitbuffer.new(self.width, h, bbtype)
    self._bb:fill(Blitbuffer.COLOR_WHITE)
    local y = font_height
    for i = start_row_idx, end_row_idx do
        local line = self.vertical_string_list[i]
        local pen_x = 0 -- when alignment == "left"
        if self.alignment == "center" then
            pen_x = (self.width - line.width)/2 or 0
        elseif self.alignment == "right" then
            pen_x = (self.width - line.width)
        end
            --@todo don't use kerning for monospaced fonts.    (houqp)
            -- refert to cb25029dddc42693cc7aaefbe47e9bd3b7e1a750 in master tree
        RenderText:renderUtf8Text(self._bb, pen_x, y, self.face, self:_getLineText(line), true, self.bold, self.fgcolor, nil, self:_getLinePads(line))
        y = y + self.line_height_px
    end

    -- Render image if any
    self:_renderImage(start_row_idx)
end

function TextBoxWidget:_renderImage(start_row_idx)
    local scheduled_update = self.scheduled_update
    self.scheduled_update = nil -- reset it, so we don't have to whenever we return below
    if not self.line_num_to_image or not self.line_num_to_image[start_row_idx] then
        return -- no image on this page
    end
    local image = self.line_num_to_image[start_row_idx]
    local do_schedule_update = false
    local display_bb = false
    local display_alt = false
    local status_text = nil
    local alt_text = image.title or ""
    if image.caption then
        alt_text = alt_text.."\n"..image.caption
    end
    -- Decide what to do/display
    if image.bb then -- we have a bb
        if scheduled_update then -- we're called from a scheduled update
            display_bb = true -- display the bb we got
        else
            -- not from a scheduled update, but update from Tap on image
            -- or we are back to this page from another one
            if self.image_show_alt_text then
                display_alt = true -- display alt_text
            else
                display_bb = true -- display the bb we have
            end
        end
    else -- no bb yet
        display_alt = true -- nothing else to display but alt_text
        if scheduled_update then -- we just failed loading a bb in a scheduled update
            status_text = "⚠" -- show a warning triangle below alt_text
        else
            -- initial display of page (or back on it and previous
            -- load_bb_func failed: try it again)
            if image.load_bb_func then -- we can load a bb
                do_schedule_update = true -- load it and call us again
                status_text = "♲"  -- display loading recycle sign below alt_text
            end
        end
    end
    -- logger.dbg("display_bb:", display_bb, "display_alt", display_alt, "status_text:", status_text, "do_schedule_update:", do_schedule_update)
    -- Do what's been decided
    if display_bb then
        -- With alpha-blending if the image contains an alpha channel
        local bbtype = image.bb:getType()
        if bbtype == Blitbuffer.TYPE_BB8A or bbtype == Blitbuffer.TYPE_BBRGB32 then
            -- NOTE: MuPDF feeds us premultiplied alpha (and we don't care w/ GifLib, as alpha is all or nothing).
            self._bb:pmulalphablitFrom(image.bb, self.width - image.width, 0)
        else
            self._bb:blitFrom(image.bb, self.width - image.width, 0)
        end
    end
    local status_height = 0
    if status_text then
        local status_widget = TextWidget:new{
            text = status_text,
            face = Font:getFace("cfont", 20),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            bold = true,
        }
        status_height = status_widget:getSize().h
        status_widget = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            margin = 0,
            padding = 0,
            RightContainer:new{
                dimen = {
                    w = image.width,
                    h = status_height,
                },
                status_widget,
            },
        }
        status_widget:paintTo(self._bb, self.width - image.width, image.height - status_height)
        status_widget:free()
    end
    if display_alt then
        local alt_widget = TextBoxWidget:new{
            text = alt_text,
            face = self.image_alt_face,
            fgcolor = self.image_alt_fgcolor,
            width = image.width,
            -- don't draw over status_text if any
            height = math.max(0, image.height - status_height),
        }
        alt_widget:paintTo(self._bb, self.width - image.width, 0)
        alt_widget:free()
    end
    if do_schedule_update then
        if self.image_update_action then
            -- Cancel any previous one, if we changed page quickly
            UIManager:unschedule(self.image_update_action)
        end
        -- Remember on which page we were launched, so we can
        -- abort if page has changed
        local scheduled_for_linenum = start_row_idx
        self.image_update_action = function()
            self.image_update_action = nil
            if scheduled_for_linenum ~= self.virtual_line_num then
                return -- no more on this page
            end
            local dismissed = image.load_bb_func() -- will update self.bb (or not if failure)
            if dismissed then
                -- If dismissed, the dismiss event may be resent, we
                -- may soon just go display another page. So delay this update a
                -- bit to see if that happened
                UIManager:scheduleIn(0.1, function()
                    if scheduled_for_linenum == self.virtual_line_num then
                        -- we are still on the same page
                        self:update(true)
                        UIManager:setDirty(self.dialog or "all", function()
                            -- return "ui", self.dimen
                            -- We can refresh only the image area, even if we have just
                            -- re-rendered the whole textbox as the text has been
                            -- rendered just the same as it was
                            return "ui", Geom:new{
                                x = self.dimen.x + self.width - image.width,
                                y = self.dimen.y,
                                w = image.width,
                                h = image.height,
                            }
                        end)
                    end
                end)
            else
                -- Image loaded (or not if failure): call us again
                -- with scheduled_update = true so we can draw what we got
                self:update(true)
                UIManager:setDirty(self.dialog or "all", function()
                    -- return "ui", self.dimen
                    -- We can refresh only the image area, even if we have just
                    -- re-rendered the whole textbox as the text has been
                    -- rendered just the same as it was
                    return "ui", Geom:new{
                        x = self.dimen.x + self.width - image.width,
                        y = self.dimen.y,
                        w = image.width,
                        h = image.height,
                    }
                end)
            end
        end
        -- Wrap it with Trapper, as load_bb_func may be using some of its
        -- dismissable methods
        local Trapper = require("ui/trapper")
        UIManager:scheduleIn(0.1, function() Trapper:wrap(self.image_update_action) end)
    end
end

function TextBoxWidget:getCharWidth(idx)
    return self.char_width[self.charlist[idx]]
end

function TextBoxWidget:getVisLineCount()
    return self.lines_per_page
end

function TextBoxWidget:getAllLineCount()
    return #self.vertical_string_list
end

function TextBoxWidget:getTextHeight()
    return self.text_height
end

function TextBoxWidget:getLineHeight()
    return self.line_height_px
end

function TextBoxWidget:getVisibleHeightRatios()
    local low = (self.virtual_line_num - 1) / #self.vertical_string_list
    local high = (self.virtual_line_num - 1 + self.lines_per_page) / #self.vertical_string_list
    return low, high
end

function TextBoxWidget:getCharPos()
    -- returns virtual_line_num too
    return self.charpos, self.virtual_line_num
end

function TextBoxWidget:getSize()
    if self.width and self.height then
        return Geom:new{ w = self.width, h = self.height}
    else
        return Geom:new{ w = self.width, h = self._bb:getHeight()}
    end
end

function TextBoxWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:blitFrom(self._bb, x, y, 0, 0, self.width, self._bb:getHeight())
end

function TextBoxWidget:free()
    logger.dbg("TextBoxWidget:free called")
    -- :free() is called when our parent widget is closing, and
    -- here whenever :_renderText() is being called, to display
    -- a new page: cancel any scheduled image update, as it
    -- is no longer related to current page
    if self.image_update_action then
        logger.dbg("TextBoxWidget:free: cancelling self.image_update_action")
        UIManager:unschedule(self.image_update_action)
    end
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
    if self.cursor_restore_bb then
        self.cursor_restore_bb:free()
        self.cursor_restore_bb = nil
    end
end

function TextBoxWidget:update(scheduled_update)
    self:free()
    -- We set this flag so :_renderText() can know we were called from a
    -- scheduled update and so not schedule another one
    self.scheduled_update = scheduled_update
    self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    self.scheduled_update = nil
end

function TextBoxWidget:onTapImage(arg, ges)
    if self.line_num_to_image and self.line_num_to_image[self.virtual_line_num] then
        local image = self.line_num_to_image[self.virtual_line_num]
        local tap_x = ges.pos.x - self.dimen.x
        local tap_y = ges.pos.y - self.dimen.y
        -- Check that this tap is on this image
        if tap_x > self.width - image.width and tap_x < self.width and
           tap_y > 0 and tap_y < image.height then
            logger.dbg("tap on image")
            if image.bb then
                -- Toggle between image and alt_text
                self.image_show_alt_text = not self.image_show_alt_text
                self:update()
                UIManager:setDirty(self.dialog or "all", function()
                    -- return "ui", self.dimen
                    -- We can refresh only the image area, even if we have just
                    -- re-rendered the whole textbox as the text has been
                    -- rendered just the same as it was
                    return "ui", Geom:new{
                        x = self.dimen.x + self.width - image.width,
                        y = self.dimen.y,
                        w = image.width,
                        h = image.height,
                    }
                end)
                return true
            end
        end
    end
end

function TextBoxWidget:scrollDown()
    self.image_show_alt_text = nil -- reset image bb/alt state
    if self.virtual_line_num + self.lines_per_page <= #self.vertical_string_list then
        self:free()
        self.virtual_line_num = self.virtual_line_num + self.lines_per_page
        -- If last line shown, set it to be the last line of view
        -- (only if editable, as this would be confusing when reading
        -- a dictionary result or a wikipedia page)
        if self.editable then
            if self.virtual_line_num > #self.vertical_string_list - self.lines_per_page + 1 then
                self.virtual_line_num = #self.vertical_string_list - self.lines_per_page + 1
                if self.virtual_line_num < 1 then
                    self.virtual_line_num = 1
                end
            end
        end
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    end
    if self.editable then
        -- move cursor to first line of visible area
        local ln = self.height == nil and 1 or self.virtual_line_num
        self:moveCursorToCharPos(self.vertical_string_list[ln] and self.vertical_string_list[ln].offset or 1)
    end
end

function TextBoxWidget:scrollUp()
    self.image_show_alt_text = nil
    if self.virtual_line_num > 1 then
        self:free()
        if self.virtual_line_num <= self.lines_per_page then
            self.virtual_line_num = 1
        else
            self.virtual_line_num = self.virtual_line_num - self.lines_per_page
        end
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    end
    if self.editable then
        -- move cursor to first line of visible area
        local ln = self.height == nil and 1 or self.virtual_line_num
        self:moveCursorToCharPos(self.vertical_string_list[ln] and self.vertical_string_list[ln].offset or 1)
    end
end

function TextBoxWidget:scrollLines(nb_lines)
    -- nb_lines can be negative
    if nb_lines == 0 then
        return
    end
    self.image_show_alt_text = nil
    local new_line_num = self.virtual_line_num + nb_lines
    if new_line_num < 1 then
        new_line_num = 1
    end
    if new_line_num > #self.vertical_string_list - self.lines_per_page + 1 then
        new_line_num = #self.vertical_string_list - self.lines_per_page + 1
    end
    self.virtual_line_num = new_line_num
    self:free()
    self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    if self.editable then
        local x, y = self:_getXYForCharPos() -- luacheck: no unused
        if y < 0 or y >= self.text_height then
            -- move cursor to first line of visible area
            local ln = self.height == nil and 1 or self.virtual_line_num
            self:moveCursorToCharPos(self.vertical_string_list[ln] and self.vertical_string_list[ln].offset or 1)
        end
    end
end

function TextBoxWidget:scrollToTop()
    self.image_show_alt_text = nil
    if self.virtual_line_num > 1 then
        self:free()
        self.virtual_line_num = 1
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    end
    if self.editable then
        -- move cursor to first char
        self:moveCursorToCharPos(1)
    end
end

function TextBoxWidget:scrollToBottom()
    self.image_show_alt_text = nil
    -- Show last line of text on last line of view
    local ln = #self.vertical_string_list - self.lines_per_page + 1
    if ln < 1 then
        ln = 1
    end
    if self.virtual_line_num ~= ln then
        self:free()
        self.virtual_line_num = ln
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    end
    if self.editable then
        -- move cursor to last char
        self:moveCursorToCharPos(#self.charlist + 1)
    end
end


function TextBoxWidget:scrollToRatio(ratio)
    self.image_show_alt_text = nil
    ratio = math.max(0, math.min(1, ratio)) -- ensure ratio is between 0 and 1 (100%)
    local page_count = 1 + math.floor((#self.vertical_string_list - 1) / self.lines_per_page)
    local page_num = 1 + Math.round((page_count - 1) * ratio)
    local line_num = 1 + (page_num - 1) * self.lines_per_page
    if line_num ~= self.virtual_line_num then
        self:free()
        self.virtual_line_num = line_num
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
    end
    if self.editable then
        -- move cursor to first line of visible area
        local ln = self.height == nil and 1 or self.virtual_line_num
        self:moveCursorToCharPos(self.vertical_string_list[ln].offset)
    end
end


--- Cursor management

-- Return the coordinates (relative to current view, so negative y is possible)
-- of the left of char at charpos (use self.charpos if none provided)
function TextBoxWidget:_getXYForCharPos(charpos)
    if not charpos then
        charpos = self.charpos
    end
    if self.text == nil or string.len(self.text) == 0 then
        return 0, 0
    end
    -- Find the line number: scan up/down from current virtual_line_num
    local ln = self.height == nil and 1 or self.virtual_line_num
    if charpos > self.vertical_string_list[ln].offset then -- after first line
        while ln < #self.vertical_string_list do
            if self.vertical_string_list[ln + 1].offset > charpos then
                break
            else
                ln = ln + 1
            end
        end
    elseif charpos < self.vertical_string_list[ln].offset then -- before first line
        while ln > 1 do
            ln = ln - 1
            if self.vertical_string_list[ln].offset <= charpos then
                break
            end
        end
    end
    local y = (ln - self.virtual_line_num) * self.line_height_px
    -- Find the x offset in the current line.
    local x = 0
    local offset = self.vertical_string_list[ln].offset
    local nbchars = #self.charlist
    while offset < charpos do
        if offset <= nbchars then -- charpos may exceed #self.charlist
            x = x + self.char_width[self.charlist[offset]] + (self.idx_pad[offset] or 0)
        end
        offset = offset + 1
    end
    -- Cursor can be drawn at x, it will be on the left of the char pointed by charpos
    -- (x=0 for first char of line - for end of line, it will be before the \n, the \n
    -- itself being not displayed)
    return x, y
end

-- Return the charpos at provided coordinates (relative to current view,
-- so negative y is allowed)
function TextBoxWidget:getCharPosAtXY(x, y)
    if #self.vertical_string_list == 0 then
        -- if there's no text at all, nothing to do
        return 1
    end
    local ln = self.height == nil and 1 or self.virtual_line_num
    ln = ln + math.floor(y / self.line_height_px)
    if ln < 1 then
        return 1 -- return start of first line
    elseif ln > #self.vertical_string_list then
        return #self.charlist + 1 -- return end of last line
    end
    if x > self.vertical_string_list[ln].width then -- no need to loop thru chars
        local pos = self.vertical_string_list[ln].end_offset
        if not pos then -- empty line
            pos = self.vertical_string_list[ln].offset
        end
        return pos + 1 -- after last char
    end
    local idx = self.vertical_string_list[ln].offset
    local end_offset = self.vertical_string_list[ln].end_offset
    if not end_offset then -- empty line
        return idx
    end
    local w = 0
    local w_prev
    while idx <= end_offset do
        w_prev = w
        w = w + self.char_width[self.charlist[idx]] + (self.idx_pad[idx] or 0)
        if w > x then -- we're on this char at idx
            if x - w_prev < w - x then -- nearest to char start
                return idx
            else -- nearest to char end: draw cursor before next char
                return idx + 1
            end
            break
        end
        idx = idx + 1
    end
    return end_offset + 1 -- should not happen
end

-- Tunables for the next function: not sure yet which combination is
-- best to get the less cursor trail - and initially got some crashes
-- when using refresh funcs. It finally feels fine with both set to true,
-- but one can turn them to false with a setting to check how some other
-- combinations do.
local CURSOR_COMBINE_REGIONS = G_reader_settings:nilOrTrue("ui_cursor_combine_regions")
local CURSOR_USE_REFRESH_FUNCS = G_reader_settings:nilOrTrue("ui_cursor_use_refresh_funcs")

-- Update charpos to the one provided; if out of current view, update
-- virtual_line_num to move it to view, and draw the cursor
function TextBoxWidget:moveCursorToCharPos(charpos)
    if not self.editable then
        -- we shouldn't have been called if not editable
        logger.warn("TextBoxWidget:moveCursorToCharPos called, but not editable")
        return
    end
    self.charpos = charpos
    self.prev_virtual_line_num = self.virtual_line_num
    local x, y = self:_getXYForCharPos() -- we can get y outside current view
    -- adjust self.virtual_line_num for overflowed y to have y in current view
    if y < 0 then
        local scroll_lines = math.ceil( -y / self.line_height_px )
        self.virtual_line_num = self.virtual_line_num - scroll_lines
        if self.virtual_line_num < 1 then
            self.virtual_line_num = 1
        end
        y = y + scroll_lines * self.line_height_px
    end
    if y >= self.text_height then
        local scroll_lines = math.floor( (y-self.text_height) / self.line_height_px ) + 1
        self.virtual_line_num = self.virtual_line_num + scroll_lines
        -- needs to deal with possible overflow ?
        y = y - scroll_lines * self.line_height_px
    end
    if not self._bb then
        return -- no bb yet to render the cursor too
    end
    if self.virtual_line_num ~= self.prev_virtual_line_num then
        -- We scrolled the view: full render and refresh needed
        self:free()
        self:_renderText(self.virtual_line_num, self.virtual_line_num + self.lines_per_page - 1)
        -- Store the original image of where we will draw the cursor, for a
        -- quick restore and two small refreshes when moving only the cursor
        self.cursor_restore_x = x
        self.cursor_restore_y = y
        self.cursor_restore_bb = Blitbuffer.new(self.cursor_line.dimen.w, self.cursor_line.dimen.h, self._bb:getType())
        self.cursor_restore_bb:blitFrom(self._bb, 0, 0, x, y, self.cursor_line.dimen.w, self.cursor_line.dimen.h)
        -- Paint the cursor, and refresh the whole widget
        self.cursor_line:paintTo(self._bb, x, y)
        UIManager:setDirty(self.dialog or "all", function()
            return "ui", self.dimen
        end)
    elseif self._bb then
        if CURSOR_USE_REFRESH_FUNCS then
            -- We didn't scroll the view, only the cursor was moved
            local restore_x, restore_y
            if self.cursor_restore_bb then
                -- Restore the previous cursor position content, and do
                -- a small ui refresh of the old cursor area
                self._bb:blitFrom(self.cursor_restore_bb, self.cursor_restore_x, self.cursor_restore_y,
                    0, 0, self.cursor_line.dimen.w, self.cursor_line.dimen.h)
                -- remember current values for use in the setDirty funcs, as
                -- we will have overriden them when these are called
                restore_x = self.cursor_restore_x
                restore_y = self.cursor_restore_y
                if not CURSOR_COMBINE_REGIONS then
                    UIManager:setDirty(self.dialog or "all", function()
                        return "ui", Geom:new{
                            x = self.dimen.x + restore_x,
                            y = self.dimen.y + restore_y,
                            w = self.cursor_line.dimen.w,
                            h = self.cursor_line.dimen.h,
                        }
                    end)
                end
                self.cursor_restore_bb:free()
                self.cursor_restore_bb = nil
            end
            -- Store the original image of where we will draw the new cursor
            self.cursor_restore_x = x
            self.cursor_restore_y = y
            self.cursor_restore_bb = Blitbuffer.new(self.cursor_line.dimen.w, self.cursor_line.dimen.h, self._bb:getType())
            self.cursor_restore_bb:blitFrom(self._bb, 0, 0, x, y, self.cursor_line.dimen.w, self.cursor_line.dimen.h)
            -- Paint the cursor, and do a small ui refresh of the new cursor area
            self.cursor_line:paintTo(self._bb, x, y)
            UIManager:setDirty(self.dialog or "all", function()
                local cursor_region = Geom:new{
                    x = self.dimen.x + x,
                    y = self.dimen.y + y,
                    w = self.cursor_line.dimen.w,
                    h = self.cursor_line.dimen.h,
                }
                if CURSOR_COMBINE_REGIONS and restore_x and restore_y then
                    local restore_region = Geom:new{
                        x = self.dimen.x + restore_x,
                        y = self.dimen.y + restore_y,
                        w = self.cursor_line.dimen.w,
                        h = self.cursor_line.dimen.h,
                    }
                    cursor_region = cursor_region:combine(restore_region)
                end
                return "ui", cursor_region
            end)
        else -- CURSOR_USE_REFRESH_FUNCS = false
            -- We didn't scroll the view, only the cursor was moved
            local restore_region
            if self.cursor_restore_bb then
                -- Restore the previous cursor position content, and do
                -- a small ui refresh of the old cursor area
                self._bb:blitFrom(self.cursor_restore_bb, self.cursor_restore_x, self.cursor_restore_y,
                    0, 0, self.cursor_line.dimen.w, self.cursor_line.dimen.h)
                if self.dimen then
                    restore_region = Geom:new{
                        x = self.dimen.x + self.cursor_restore_x,
                        y = self.dimen.y + self.cursor_restore_y,
                        w = self.cursor_line.dimen.w,
                        h = self.cursor_line.dimen.h,
                    }
                    if not CURSOR_COMBINE_REGIONS then
                        UIManager:setDirty(self.dialog or "all", "ui", restore_region)
                    end
                end
                self.cursor_restore_bb:free()
                self.cursor_restore_bb = nil
            end
            -- Store the original image of where we will draw the new cursor
            self.cursor_restore_x = x
            self.cursor_restore_y = y
            self.cursor_restore_bb = Blitbuffer.new(self.cursor_line.dimen.w, self.cursor_line.dimen.h, self._bb:getType())
            self.cursor_restore_bb:blitFrom(self._bb, 0, 0, x, y, self.cursor_line.dimen.w, self.cursor_line.dimen.h)
            -- Paint the cursor, and do a small ui refresh of the new cursor area
            self.cursor_line:paintTo(self._bb, x, y)
            if self.dimen then
                local cursor_region = Geom:new{
                    x = self.dimen.x + x,
                    y = self.dimen.y + y,
                    w = self.cursor_line.dimen.w,
                    h = self.cursor_line.dimen.h,
                }
                if CURSOR_COMBINE_REGIONS and restore_region then
                    cursor_region = cursor_region:combine(restore_region)
                end
                UIManager:setDirty(self.dialog or "all", "ui", cursor_region)
            end
        end
    end
end

function TextBoxWidget:moveCursorToXY(x, y, restrict_to_view)
    if restrict_to_view then
        -- Wrap y to current view (when getting coordinates from gesture)
        -- (no real need to check for x, getCharPosAtXY() is ok with any x)
        if y < 0 then
            y = 0
        end
        if y >= self.text_height then
            y = self.text_height - 1
        end
    end
    local charpos = self:getCharPosAtXY(x, y)
    self:moveCursorToCharPos(charpos)
end

-- Update self.virtual_line_num to the page containing charpos
function TextBoxWidget:scrollViewToCharPos()
    if self.top_line_num then
        -- if previous top_line_num provided, go to that line
        self.virtual_line_num = self.top_line_num
        if self.virtual_line_num < 1 then
            self.virtual_line_num = 1
        end
        if self.virtual_line_num > #self.vertical_string_list then
            self.virtual_line_num = #self.vertical_string_list
        end
        -- Ensure we don't show too much blank at end (when deleting last lines)
        -- local max_empty_lines =  math.floor(self.lines_per_page / 2)
        -- Best to not allow any, for initially non-scrolled widgets
        local max_empty_lines =  0
        local max_virtual_line_num = #self.vertical_string_list - self.lines_per_page + 1 + max_empty_lines
        if self.virtual_line_num > max_virtual_line_num then
            self.virtual_line_num = max_virtual_line_num
            if self.virtual_line_num < 1 then
                self.virtual_line_num = 1
            end
        end
        -- and adjust if cursor is out of view
        self:moveCursorToCharPos(self.charpos)
        return
    end
    -- Otherwise, find the "hard" page containing charpos
    local ln = 1
    while true do
        local lend = ln + self.lines_per_page - 1
        if lend >= #self.vertical_string_list then
            break -- last page
        end
        if self.vertical_string_list[lend+1].offset >= self.charpos then
            break
        end
        ln = ln + self.lines_per_page
    end
    self.virtual_line_num = ln
end

function TextBoxWidget:moveCursorLeft()
    if self.charpos > 1 then
        self:moveCursorToCharPos(self.charpos-1)
    end
end

function TextBoxWidget:moveCursorRight()
    if self.charpos < #self.charlist + 1 then -- we can move after last char
        self:moveCursorToCharPos(self.charpos+1)
    end
end

function TextBoxWidget:moveCursorUp()
    if self.vertical_string_list and #self.vertical_string_list < 2 then return end
    local x, y = self:_getXYForCharPos()
    self:moveCursorToXY(x, y - self.line_height_px)
end

function TextBoxWidget:moveCursorDown()
    if self.vertical_string_list and #self.vertical_string_list < 2 then return end
    local x, y = self:_getXYForCharPos()
    self:moveCursorToXY(x, y + self.line_height_px)
end


--- Text selection with Hold

-- Allow selection of a single word at hold position
function TextBoxWidget:onHoldWord(callback, ges)
    if not callback then return end

    local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    local line_num = math.ceil(y / self.line_height_px) + self.virtual_line_num-1
    local line = self.vertical_string_list[line_num]
    logger.dbg("holding on line", line)
    if line then
        local char_start = line.offset
        local char_end  -- char_end is non-inclusive
        if line_num >= #self.vertical_string_list then
            char_end = #self.charlist + 1
        else
            char_end = self.vertical_string_list[line_num+1].offset
        end
        local char_probe_x = 0
        local idx = char_start
        -- find which character the touch is holding
        while idx < char_end do
            -- FIXME: this might break if kerning is enabled
            char_probe_x = char_probe_x + self.char_width[self.charlist[idx]] + (self.idx_pad[idx] or 0)
            if char_probe_x > x then
                -- ignore spaces
                if self.charlist[idx] == " " then break end
                -- now find which word the character is in
                local words = util.splitToWords(self:_getLineText(line))
                local probe_idx = char_start
                for _, w in ipairs(words) do
                    -- +1 for word separtor
                    probe_idx = probe_idx + #util.splitToChars(w)
                    if idx <= probe_idx - 1 then
                        callback(w)
                        return
                    end
                end
                break
            end
            idx = idx + 1
        end
    end

    return
end

-- Allow selection of one or more words (with no visual feedback)
-- Gestures should be declared in widget using us (e.g dictquicklookup.lua)

-- Constants for which side of a word to find
local FIND_START = 1
local FIND_END = 2

function TextBoxWidget:onHoldStartText(_, ges)
    -- store hold start position and timestamp, will be used on release
    self.hold_start_x = ges.pos.x - self.dimen.x
    self.hold_start_y = ges.pos.y - self.dimen.y

    -- check coordinates are actually inside our area
    if self.hold_start_x < 0 or self.hold_start_x > self.dimen.w or
        self.hold_start_y < 0 or self.hold_start_y > self.dimen.h then
        self.hold_start_tv = nil -- don't process coming HoldRelease event
        return false -- let event be processed by other widgets
    end

    self.hold_start_tv = TimeVal.now()
    return true
end

function TextBoxWidget:onHoldPanText(_, ges)
    -- We don't highlight the currently selected text, but just let this
    -- event pop up if we are not currently selecting text
    if not self.hold_start_tv then
        return false
    end
    -- Don't let that event be processed by other widget
    return true
end

function TextBoxWidget:onHoldReleaseText(callback, ges)
    if not callback then return end

    local hold_end_x = ges.pos.x - self.dimen.x
    local hold_end_y = ges.pos.y - self.dimen.y

    -- check we have seen a HoldStart event
    if not self.hold_start_tv then
        return false
    end
    -- check start and end coordinates are actually inside our area
    if self.hold_start_x < 0 or hold_end_x < 0 or
        self.hold_start_x > self.dimen.w or hold_end_x > self.dimen.w or
        self.hold_start_y < 0 or hold_end_y < 0 or
        self.hold_start_y > self.dimen.h or hold_end_y > self.dimen.h then
        return false
    end

    local hold_duration = TimeVal.now() - self.hold_start_tv
    hold_duration = hold_duration.sec + hold_duration.usec/1000000

    -- If page contains an image, check if Hold is on this image and deal
    -- with it directly
    if self.line_num_to_image and self.line_num_to_image[self.virtual_line_num] then
        local image = self.line_num_to_image[self.virtual_line_num]
        if hold_end_x > self.width - image.width and hold_end_y < image.height then
            -- Only if low-res image is loaded, so we have something to display
            -- if high-res loading is not implemented or if its loading fails
            if image.bb then
                logger.dbg("hold on image")
                local load_and_show_image = function()
                    if not image.hi_bb and image.load_bb_func then
                        image.load_bb_func(true) -- load high res image if implemented
                    end
                    -- display hi_bb, or low-res bb if hi_bb has not been
                    -- made (if not implemented, or failed, or dismissed)
                    local ImageViewer = require("ui/widget/imageviewer")
                    local imgviewer = ImageViewer:new{
                        image = image.hi_bb or image.bb, -- fallback to low-res if high-res failed
                        image_disposable = false, -- we may re-use our bb if called again
                        with_title_bar = true,
                        title_text = image.title,
                        caption = image.caption,
                        fullscreen = true,
                    }
                    UIManager:show(imgviewer)
                end
                -- Wrap it with Trapper, as load_bb_func may be using some of its
                -- dismissable methods
                local Trapper = require("ui/trapper")
                UIManager:scheduleIn(0.1, function() Trapper:wrap(load_and_show_image) end)
                -- And we return without calling the "Hold on text" callback
                return true
            end
        end
    end
    -- Swap start and end if needed
    local x0, y0, x1, y1
    -- first, sort by y/line_num
    local start_line_num = math.ceil(self.hold_start_y / self.line_height_px)
    local end_line_num = math.ceil(hold_end_y / self.line_height_px)
    if start_line_num < end_line_num then
        x0, y0 = self.hold_start_x, self.hold_start_y
        x1, y1 = hold_end_x, hold_end_y
    elseif start_line_num > end_line_num then
        x0, y0 = hold_end_x, hold_end_y
        x1, y1 = self.hold_start_x, self.hold_start_y
    else -- same line_num : sort by x
        if self.hold_start_x <= hold_end_x then
            x0, y0 = self.hold_start_x, self.hold_start_y
            x1, y1 = hold_end_x, hold_end_y
        else
            x0, y0 = hold_end_x, hold_end_y
            x1, y1 = self.hold_start_x, self.hold_start_y
        end
    end

    -- Reset start infos, so we do not reuse them and can catch
    -- a missed start event
    self.hold_start_x = nil
    self.hold_start_y = nil
    self.hold_start_tv = nil

    -- similar code to find start or end is in _findWordEdge() helper
    local sel_start_idx = self:_findWordEdge(x0, y0, FIND_START)
    local sel_end_idx = self:_findWordEdge(x1, y1, FIND_END)

    if not sel_start_idx or not sel_end_idx then
        -- one or both hold points were out of text
        return true
    end

    local selected_text = table.concat(self.charlist, "", sel_start_idx, sel_end_idx)
    logger.dbg("onHoldReleaseText (duration:", hold_duration, ") :", sel_start_idx, ">", sel_end_idx, "=", selected_text)
    callback(selected_text, hold_duration)
    return true
end

function TextBoxWidget:_findWordEdge(x, y, side)
    if side ~= FIND_START and side ~= FIND_END then
        return
    end
    local line_num = math.ceil(y / self.line_height_px) + self.virtual_line_num-1
    local line = self.vertical_string_list[line_num]
    if not line then
        return -- below last line : no selection
    end
    local char_start = line.offset
    local char_end  -- char_end is non-inclusive
    if line_num >= #self.vertical_string_list then
        char_end = #self.charlist + 1
    else
        char_end = self.vertical_string_list[line_num+1].offset
    end
    local char_probe_x = 0
    local idx = char_start
    local edge_idx = nil
    -- find which character the touch is holding
    while idx < char_end do
        char_probe_x = char_probe_x + self.char_width[self.charlist[idx]] + (self.idx_pad[idx] or 0)
        if char_probe_x > x then
            -- character found, find which word the character is in, and
            -- get its start/end idx
            local words = util.splitToWords(self:_getLineText(line))
            -- words may contain separators (space, punctuation) : we don't
            -- discriminate here, it's the caller job to clean what was
            -- selected
            local probe_idx = char_start
            local next_probe_idx
            for _, w in ipairs(words) do
                next_probe_idx = probe_idx + #util.splitToChars(w)
                if idx < next_probe_idx then
                    if side == FIND_START then
                        edge_idx = probe_idx
                    elseif side == FIND_END then
                        edge_idx = next_probe_idx - 1
                    end
                    break
                end
                probe_idx = next_probe_idx
            end
            if edge_idx then
                break
            end
        end
        idx = idx + 1
    end
    return edge_idx
end

return TextBoxWidget
