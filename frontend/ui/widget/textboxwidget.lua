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
local logger = require("logger")
local util = require("util")
local Screen = require("device").screen

local TextBoxWidget = InputContainer:new{
    text = nil,
    charlist = nil,
    charpos = nil,
    char_width_list = nil, -- list of widths of the chars in `charlist`.
    vertical_string_list = nil,
    editable = false, -- Editable flag for whether drawing the cursor or not.
    justified = false, -- Should text be justified (spaces widened to fill width)
    alignment = "left", -- or "center", "right"
    cursor_line = nil, -- LineWidget to draw the vertical cursor.
    face = nil,
    bold = nil,
    line_height = 0.3, -- in em
    fgcolor = Blitbuffer.COLOR_BLACK,
    width = Screen:scaleBySize(400), -- in pixels
    height = nil, -- nil value indicates unscrollable text widget
    virtual_line_num = 1, -- used by scroll bar
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
    --    hi_bb     the low-resolution image
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
    self.line_height_px = (1 + self.line_height) * self.face.size
    self.cursor_line = LineWidget:new{
        dimen = Geom:new{
            w = Size.line.medium,
            h = self.line_height_px,
        }
    }
    self:_evalCharWidthList()
    self:_splitCharWidthList()
    if self.height == nil then
        self:_renderText(1, #self.vertical_string_list)
    else
        -- luajit may segfault if we were provided with a negative height
        if self.height < 0 then
            self.height = 0
        end
        self:_renderText(1, self:getVisLineCount())
    end
    if self.editable then
        local x, y
        x, y = self:_findCharPos()
        self.cursor_line:paintTo(self._bb, x, y)
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
    self:init()
end

function TextBoxWidget:focus()
    self.editable = true
    self:init()
end

-- Split `self.text` into `self.charlist` and evaluate the width of each char in it.
function TextBoxWidget:_evalCharWidthList()
    if self.charlist == nil then
        self.charlist = util.splitToChars(self.text)
        self.charpos = #self.charlist + 1
    end
    self.char_width_list = {}
    -- use a cache to avoid many calls to RenderText:sizeUtf8Text()
    local char_width_cache = {}
    for _, v in ipairs(self.charlist) do
        local w = char_width_cache[v]
        if w == nil then
            w = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.face, v, true, self.bold).x
            char_width_cache[v] = w
        end
        table.insert(self.char_width_list, {char = v, width = w, pad = 0})
        -- pad will be updated if we do text justification
    end
end

-- Split the text into logical lines to fit into the text box.
function TextBoxWidget:_splitCharWidthList()
    self.vertical_string_list = {}

    local idx = 1
    local size = #self.char_width_list
    local ln = 1
    local offset, cur_line_width, cur_line_text

    local lines_per_page
    if self.height then
        lines_per_page = self:getVisLineCount()
    end
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
            if (lines_per_page and ln % lines_per_page == 1) -- first line of a scrolled page
            or (lines_per_page == nil and ln == 1) then  -- first line if not scrollabled
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

        offset = idx
        -- Appending chars until the accumulated width exceeds `targeted_width`,
        -- or a newline occurs, or no more chars to consume.
        cur_line_width = 0
        local hard_newline = false
        local char_pads = nil
        while idx <= size do
            if self.char_width_list[idx].char == "\n" then
                hard_newline = true
                break
            end
            cur_line_width = cur_line_width + self.char_width_list[idx].width
            if cur_line_width > targeted_width then break else idx = idx + 1 end
        end
        if cur_line_width <= targeted_width then -- a hard newline or end of string
            cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
        else
            -- Backtrack the string until the length fit into one line.
            -- We'll give next and prev chars to isSplittable() for a wiser decision
            local c = self.char_width_list[idx].char
            local next_c = idx+1 <= size and self.char_width_list[idx+1].char or false
            local prev_c = idx-1 >= 1 and self.char_width_list[idx-1].char or false
            local adjusted_idx = idx
            local adjusted_width = cur_line_width
            while adjusted_idx > offset and not util.isSplittable(c, next_c, prev_c) do
                adjusted_width = adjusted_width - self.char_width_list[adjusted_idx].width
                adjusted_idx = adjusted_idx - 1
                next_c = c
                c = prev_c
                prev_c = adjusted_idx-1 >= 1 and self.char_width_list[adjusted_idx-1].char or false
            end
            if adjusted_idx == offset or adjusted_idx == idx then
                -- either a very long english word ocuppying more than one line,
                -- or the excessive char is itself splittable:
                -- we let that excessive char for next line
                if adjusted_idx == offset then -- let the fact a long word was splitted be known
                    self.has_split_inside_word = true
                end
                cur_line_text = table.concat(self.charlist, "", offset, idx - 1)
                cur_line_width = cur_line_width - self.char_width_list[idx].width
            elseif c == " " then
                -- we backtracked and we're below max width, but the last char
                -- is a space, we can ignore it
                cur_line_text = table.concat(self.charlist, "", offset, adjusted_idx - 1)
                cur_line_width = adjusted_width - self.char_width_list[adjusted_idx].width
                idx = adjusted_idx + 1
            else
                -- we backtracked and we're below max width, we can leave the
                -- splittable char on this line
                cur_line_text = table.concat(self.charlist, "", offset, adjusted_idx)
                cur_line_width = adjusted_width
                idx = adjusted_idx + 1
            end
            if self.justified then
                -- this line was splitted and can be justified
                -- we build a list of char_pads, pixels to add to some chars to make the
                -- whole line justified
                local fill_width = targeted_width - cur_line_width
                if fill_width > 0 then
                    local _, nbspaces = string.gsub(cur_line_text, " ", "")
                    if nbspaces > 0 then
                        -- width added to all spaces
                        local space_add_w = math.floor(fill_width / nbspaces)
                        -- nb of spaces to which we'll add 1 more pixel
                        local space_add1_nb = fill_width - space_add_w * nbspaces
                        char_pads = {}
                        for cidx = offset, idx-1 do
                            local pad = 0
                            if self.char_width_list[cidx].char == " " then
                                pad = space_add_w
                                if space_add1_nb > 0 then
                                    pad = pad + 1
                                    space_add1_nb = space_add1_nb - 1
                                end
                                -- Update pad info, help for hold position accuracy
                                self.char_width_list[cidx].pad = pad
                            end
                            table.insert(char_pads, pad)
                        end
                    else
                        -- very long word, or CJK text with no space
                        -- pad first chars with 1 pixel
                        char_pads = {}
                        for cidx = offset, idx-1 do
                            local pad = 0
                            if fill_width > 0 then
                                pad = 1
                                fill_width = fill_width - 1
                                -- Update pad info, help for hold position accuracy
                                self.char_width_list[cidx].pad = pad
                            end
                            table.insert(char_pads, pad)
                        end
                    end
                end
            end
        end -- endif cur_line_width > targeted_width
        if cur_line_width < 0 then break end
        self.vertical_string_list[ln] = {
            text = cur_line_text,
            offset = offset,
            width = cur_line_width,
            char_pads = char_pads,
        }
        if hard_newline then
            idx = idx + 1
            -- FIXME: reuse newline entry
            self.vertical_string_list[ln+1] = {text = "", offset = idx, width = 0}
        else
            -- If next char is a space, discard it so it does not become
            -- an ugly leading space on the next line
            if idx <= size and self.char_width_list[idx].char == " " then
                idx = idx + 1
            end
        end
        ln = ln + 1
        -- Make sure `idx` point to the next char to be processed in the next loop.
    end
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
        -- Whether Screen:isColorEnabled() or not, it's best to always use BBRGB32
        -- and alphablitFrom() for the best display of various images:
        --   With greyscale screen TYPE_BB8 (the default, and what we would
        --   have chosen when not Screen:isColorEnabled()):
        --     alphablitFrom: some images are all white (ex: flags on Milan, Ilkhanides on wiki.fr)
        --     blitFrom: some images have a black background (ex: RDA, Allemagne on wiki.fr)
        --   With TYPE_BBRGB32:
        --     blitFrom: some images have a black background (ex: RDA, Allemagne on wiki.fr)
        --     alphablitFrom: all these images looks good, with a white background
        bbtype = Blitbuffer.TYPE_BBRGB32
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
        RenderText:renderUtf8Text(self._bb, pen_x, y, self.face, line.text, true, self.bold, self.fgcolor, nil, line.char_pads)
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
        self._bb:alphablitFrom(image.bb, self.width - image.width, 0)
    end
    local status_height = 0
    if status_text then
        local status_widget = TextWidget:new{
            text = status_text,
            face = Font:getFace("cfont", 20),
            fgcolor = Blitbuffer.COLOR_GREY,
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
                        UIManager:setDirty("all", function()
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
                UIManager:setDirty("all", function()
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

-- Return the position of the cursor corresponding to `self.charpos`,
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:_findCharPos()
    if self.text == nil or string.len(self.text) == 0 then
        return 0, 0
    end
    -- Find the line number.
    local ln = self.height == nil and 1 or self.virtual_line_num
    while ln + 1 <= #self.vertical_string_list do
        if self.vertical_string_list[ln + 1].offset > self.charpos then
            break
        else
            ln = ln + 1
        end
    end
    -- Find the offset at the current line.
    local x = 0
    local offset = self.vertical_string_list[ln].offset
    while offset < self.charpos do
        x = x + self.char_width_list[offset].width + self.char_width_list[offset].pad
        offset = offset + 1
    end
    return x + 1, (ln - 1) * self.line_height_px -- offset `x` by 1 to avoid overlap
end

function TextBoxWidget:moveCursorToCharpos(charpos)
    self.charpos = charpos
    local x, y = self:_findCharPos()
    self.cursor_line:paintTo(self._bb, x, y)
end

-- Click event: Move the cursor to a new location with (x, y), in pixels.
-- Be aware of virtual line number of the scorllTextWidget.
function TextBoxWidget:moveCursor(x, y)
    if x < 0 or y < 0 then return end
    if #self.vertical_string_list == 0 then
        -- if there's no text at all, nothing to do
        return 1
    end
    local w = 0
    local ln = self.height == nil and 1 or self.virtual_line_num
    ln = ln + math.ceil(y / self.line_height_px) - 1
    if ln > #self.vertical_string_list then
        ln = #self.vertical_string_list
        x = self.width
    end
    local offset = self.vertical_string_list[ln].offset
    local idx = ln == #self.vertical_string_list and #self.char_width_list or self.vertical_string_list[ln + 1].offset - 1
    while offset <= idx do
        w = w + self.char_width_list[offset].width + self.char_width_list[offset].pad
        if w > x then break else offset = offset + 1 end
    end
    if w > x then
        local w_prev = w - self.char_width_list[offset].width - self.char_width_list[offset].pad
        if x - w_prev < w - x then -- the previous one is more closer
            w = w_prev
        else
            offset = offset + 1
        end
    end
    self:free()
    self:_renderText(1, #self.vertical_string_list)
    self.cursor_line:paintTo(self._bb, w + 1,
                             (ln - self.virtual_line_num) * self.line_height_px)
    return offset
end

function TextBoxWidget:getVisLineCount()
    return math.floor(self.height / self.line_height_px)
end

function TextBoxWidget:getAllLineCount()
    return #self.vertical_string_list
end

function TextBoxWidget:update(scheduled_update)
    self:free()
    -- We set this flag so :_renderText() can know we were called from a
    -- scheduled update and so not schedule another one
    self.scheduled_update = scheduled_update
    self:_renderText(self.virtual_line_num, self.virtual_line_num + self:getVisLineCount() - 1)
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
                UIManager:setDirty("all", function()
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

-- TODO: modify `charpos` so that it can render the cursor
function TextBoxWidget:scrollDown()
    self.image_show_alt_text = nil -- reset image bb/alt state
    local visible_line_count = self:getVisLineCount()
    if self.virtual_line_num + visible_line_count <= #self.vertical_string_list then
        self:free()
        self.virtual_line_num = self.virtual_line_num + visible_line_count
        self:_renderText(self.virtual_line_num, self.virtual_line_num + visible_line_count - 1)
    end
    return (self.virtual_line_num - 1) / #self.vertical_string_list, (self.virtual_line_num - 1 + visible_line_count) / #self.vertical_string_list
end

-- TODO: modify `charpos` so that it can render the cursor
function TextBoxWidget:scrollUp()
    self.image_show_alt_text = nil
    local visible_line_count = self:getVisLineCount()
    if self.virtual_line_num > 1 then
        self:free()
        if self.virtual_line_num <= visible_line_count then
            self.virtual_line_num = 1
        else
            self.virtual_line_num = self.virtual_line_num - visible_line_count
        end
        self:_renderText(self.virtual_line_num, self.virtual_line_num + visible_line_count - 1)
    end
    return (self.virtual_line_num - 1) / #self.vertical_string_list, (self.virtual_line_num - 1 + visible_line_count) / #self.vertical_string_list
end

function TextBoxWidget:getSize()
    if self.width and self.height then
        return Geom:new{ w = self.width, h = self.height}
    else
        return Geom:new{ w = self.width, h = self._bb:getHeight()}
    end
end

function TextBoxWidget:moveCursorUp()
    if self.vertical_string_list and #self.vertical_string_list < 2 then return end
    local x, y
    x, y = self:_findCharPos()
    local charpos = self:moveCursor(x, y - self.line_height_px +1)
    if charpos then
        self:moveCursorToCharpos(charpos)
    end
end

function TextBoxWidget:moveCursorDown()
    if self.vertical_string_list and #self.vertical_string_list < 2 then return end
    local x, y
    x, y = self:_findCharPos()
    local charpos = self:moveCursor(x, y + self.line_height_px +1)
    if charpos then
        self:moveCursorToCharpos(charpos)
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
    -- is no more related to current page
    if self.image_update_action then
        logger.dbg("TextBoxWidget:free: cancelling self.image_update_action")
        UIManager:unschedule(self.image_update_action)
    end
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

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
            char_end = #self.char_width_list + 1
        else
            char_end = self.vertical_string_list[line_num+1].offset
        end
        local char_probe_x = 0
        local idx = char_start
        -- find which character the touch is holding
        while idx < char_end do
            local c = self.char_width_list[idx]
            -- FIXME: this might break if kerning is enabled
            char_probe_x = char_probe_x + c.width + c.pad
            if char_probe_x > x then
                -- ignore spaces
                if c.char == " " then break end
                -- now find which word the character is in
                local words = util.splitToWords(line.text)
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
    -- just store hold start position and timestamp, will be used on release
    self.hold_start_x = ges.pos.x - self.dimen.x
    self.hold_start_y = ges.pos.y - self.dimen.y
    self.hold_start_tv = TimeVal.now()
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
                return
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
        char_end = #self.char_width_list + 1
    else
        char_end = self.vertical_string_list[line_num+1].offset
    end
    local char_probe_x = 0
    local idx = char_start
    local edge_idx = nil
    -- find which character the touch is holding
    while idx < char_end do
        local c = self.char_width_list[idx]
        char_probe_x = char_probe_x + c.width + c.pad
        if char_probe_x > x then
            -- character found, find which word the character is in, and
            -- get its start/end idx
            local words = util.splitToWords(line.text)
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
