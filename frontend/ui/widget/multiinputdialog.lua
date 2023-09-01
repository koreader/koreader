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
    description_padding = Size.padding.default,
    description_margin = Size.margin.small,
    bottom_v_padding = Size.padding.default,
}

function MultiInputDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    local VerticalGroupData = VerticalGroup:new{
        align = "left",
        self.title_bar,
    }

    self.input_field = {}
    local input_description = {}
    for i, field in ipairs(self.fields) do
        self.input_field[i] = InputText:new{
            text = field.text or "",
            hint = field.hint or "",
            input_type = field.input_type or "string",
            text_type =  field.text_type,
            face = self.input_face,
            width = math.floor(self.width * 0.9),
            focused = i == 1 and true or false,
            scroll = false,
            parent = self,
            padding = field.padding or nil,
            margin = field.margin or nil,
            -- Allow these to be specified per field if needed
            alignment = field.alignment or self.alignment,
            justified = field.justified or self.justified,
            lang = field.lang or self.lang,
            para_direction_rtl = field.para_direction_rtl or self.para_direction_rtl,
            auto_para_direction = field.auto_para_direction or self.auto_para_direction,
            alignment_strict = field.alignment_strict or self.alignment_strict,
        }
        table.insert(self.layout, #self.layout, {self.input_field[i]})
        if field.description then
            input_description[i] = FrameContainer:new{
                padding = self.description_padding,
                margin = self.description_margin,
                bordersize = 0,
                TextBoxWidget:new{
                    text = field.description,
                    face = Font:getFace("x_smallinfofont"),
                    width = math.floor(self.width * 0.9),
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
                h = self.input_field[i]:getSize().h,
            },
            self.input_field[i],
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

    self._input_widget = self.input_field[1]

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        ignore_if_over = "height",
        self.dialog_frame,
    }
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)

end

--- Returns an array of our input field's *text* field.
function MultiInputDialog:getFields()
    local fields = {}
    for i, field in ipairs(self.input_field) do
        table.insert(fields, field:getText())
    end
    return fields
end

--- BEWARE: Live ref to an internal component!
function MultiInputDialog:getRawFields()
    return self.input_field
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

    -- Make sure we have a (new) visible keyboard
    self:onShowKeyboard()
end

return MultiInputDialog

