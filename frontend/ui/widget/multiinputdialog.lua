--[[--
Widget for taking multiple user inputs.

Example for input of two strings and a number:

    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local @{ui.uimanager|UIManager} = require("ui/uimanager")
    local @{gettext|_} = require("gettext")

    local sample_input
    sample_input = MultiInputDialog:new{
        title = _("Title to show"),
        fields = {
            {
                description = _("Describe this field"),
                -- input_type = nil, -- default for text
                text = _("First input"),
                hint = _("Name"),
            },
            {
                text = "",
                hint = _("Address"),
            },
            {
                description = _("Enter a number"),
                input_type = "number",
                text = 666,
                hint = 123,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(sample_input)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        -- do something
                    end
                },
                {
                    text = _("Use settings"),
                    callback = function(touchmenu_instance)
                        local fields = sample_input:getFields()
                        -- check for user input
                        if fields[1] ~= "" and fields[2] ~= ""
                            and fields[3] ~= 0 then
                            -- insert code here
                            UIManager:close(sample_input)
                            -- If we have a touch menu: Update menu entries,
                            -- when called from a menu
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        else
                            -- not all fields where entered
                        end
                    end
                },
            },
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()


It is strongly recommended to use a text describing the action to be
executed, as demonstrated in the example above. If the resulting phrase would be
longer than three words it should just read "OK".
--]]--


local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local MultiInputDialog = InputDialog:extend{
    fields = nil, -- array, mandatory
    input_fields = nil, -- array
    focused_field_idx = 1,
    description_padding = Size.padding.default,
    description_margin = Size.margin.small,
    bottom_v_padding = Size.padding.default,
    enter_callback = nil, -- applied to all fields
}

function MultiInputDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    -- Kick InputDialog's own field out of the layout, we're not using it
    table.remove(self.layout, 1)
    -- Also murder said input field *and* its VK, or we get two of them and shit gets hilariously broken real fast...
    self:onCloseKeyboard()
    self._input_widget:onCloseWidget()

    local VerticalGroupData = VerticalGroup:new{
        align = "left",
        self.title_bar,
    }
    local content_width = math.floor(self.width * 0.9)

    -- In case of reinit, murder our previous input widgets to prevent stale VK instances from lingering
    if self.input_fields then
        for i, widget in ipairs(self.input_fields) do
            widget:onCloseWidget()
        end
    end
    self.input_fields = {}
    local input_description = {}
    for i, field in ipairs(self.fields) do
        local input_field_tmp = InputText:new{
            text = field.text,
            hint = field.hint,
            input_type = field.input_type,
            text_type = field.text_type, -- "password"
            face = self.input_face,
            width = content_width,
            idx = i,
            focused = i == self.focused_field_idx,
            scroll = false,
            parent = self,
            padding = field.padding,
            margin = field.margin,
            -- Allow these to be specified per field if needed
            alignment = field.alignment or self.alignment,
            justified = field.justified or self.justified,
            lang = field.lang or self.lang,
            para_direction_rtl = field.para_direction_rtl or self.para_direction_rtl,
            auto_para_direction = field.auto_para_direction or self.auto_para_direction,
            alignment_strict = field.alignment_strict or self.alignment_strict,
            enter_callback = self.enter_callback,
        }
        table.insert(self.input_fields, input_field_tmp)
        --- @fixme: This is semi-broken when text_type is password, as we actually end up with the checkbox instead of the field,
        --          and a "Press" on the checkbox will actually focus the password field and *not* check the box.
        -- addWidget may have added stuff below us, so make sure we insert above that...
        table.insert(self.layout, i, { input_field_tmp })
        if field.description then
            input_description[i] = FrameContainer:new{
                padding = self.description_padding,
                margin = self.description_margin,
                bordersize = 0,
                TextBoxWidget:new{
                    text = field.description,
                    face = Font:getFace("x_smallinfofont"),
                    width = content_width,
                }
            }
            table.insert(VerticalGroupData, CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = input_description[i]:getSize().h ,
                },
                input_description[i],
            })
        end
        table.insert(VerticalGroupData, CenterContainer:new{
            dimen = Geom:new{
                w = self.title_bar:getSize().w,
                h = input_field_tmp:getSize().h,
            },
            input_field_tmp,
        })
    end

    -- Add same vertical space after than before InputText
    table.insert(VerticalGroupData,CenterContainer:new{
        dimen = Geom:new{
            w = self.title_bar:getSize().w,
            h = self.description_padding + self.description_margin,
        },
        VerticalSpan:new{ width = self.description_padding + self.description_margin },
    })
    -- buttons
    table.insert(VerticalGroupData,CenterContainer:new{
        dimen = Geom:new{
            w = self.title_bar:getSize().w,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    })

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroupData,
    }

    self._input_widget = self.input_fields[self.focused_field_idx]

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        ignore_if_over = "height",
        self.dialog_frame,
    }

    if self._added_widgets then
        for _, widget in ipairs(self._added_widgets) do
            self:addWidget(widget, true)
        end
    end

    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)

end

function MultiInputDialog:getFields()
    local fields = {}
    for i, field in ipairs(self.input_fields) do
        table.insert(fields, field:getText())
    end
    return fields
end

function MultiInputDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self._input_widget:unfocus()
    -- and close its existing keyboard (via InputDialog's thin wrapper around _input_widget's own method)
    self:onCloseKeyboard()

    UIManager:setDirty(nil, function()
        return "ui", self.dialog_frame.dimen
    end)

    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self.focused_field_idx = inputbox.idx

    if (Device:hasKeyboard() or Device:hasScreenKB()) and G_reader_settings:isFalse("virtual_keyboard_enabled") then
         -- do not load virtual keyboard when user is hiding it.
         return
     end
     -- Otherwise make sure we have a (new) visible keyboard
    self:onShowKeyboard()
end

function MultiInputDialog:onKeyboardHeightChanged()
    local visible = self:isKeyboardVisible()
    local fields = self.input_fields -- backup entered text
    self:onClose() -- will close keyboard and save view position
    self._input_widget:onCloseWidget() -- proper cleanup of InputText and its keyboard
    if self._added_widgets then
        -- prevent these externally added widgets from being freed as :init() will re-add them
        local vgroup = self.dialog_frame[1]
        for i = 1, #self._added_widgets do
            table.remove(vgroup, #vgroup-2)
        end
    end
    self:free()
    self.keyboard_visible = visible
    for i, field in ipairs(self.fields) do -- restore entered text
        field.text = fields[i].text
    end
    self:init()
    if self.keyboard_visible then
        self:onShowKeyboard()
    end
    UIManager:setDirty("all", "flashui")
end

function MultiInputDialog:addWidget(widget, re_init)
    table.insert(self.layout, #self.layout, {widget})
    if not re_init then -- backup widget for re-init
        widget = CenterContainer:new{
            dimen = Geom:new{
                w = self.width,
                h = widget:getSize().h,
            },
            widget,
        }
        if not self._added_widgets then
            self._added_widgets = {}
        end
        table.insert(self._added_widgets, widget)
    end
    -- insert widget before the bottom buttons and their previous vspan
    local vgroup = self.dialog_frame[1]
    table.insert(vgroup, #vgroup-1, widget)
end

return MultiInputDialog
