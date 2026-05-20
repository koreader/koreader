-- widget test utility
-- usage: ./luajit tools/wtest.lua

require("setupkoenv")

-- Load default settings
G_defaults = require("luadefaults"):open()

local DataStorage = require("datastorage")
local _ = require("gettext")

-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir().."/settings.reader.lua")
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end
local Device = require("device")
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)
local UIManager = require("ui/uimanager")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Menu = require("ui/widget/menu")
local Widget = require("ui/widget/widget")
local TextWidget = require("ui/widget/textwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local AlphaContainer = require("ui/widget/container/alphacontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local TouchMenu = require("ui/widget/touchmenu")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("apps/reader/readerui")
local DEBUG = require("dbg")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local InputText = require("ui/widget/inputtext")

DEBUG:turnOn()

-----------------------------------------------------
-- widget that paints the grid on the background
-----------------------------------------------------
TestGrid = Widget:new{}
TestVisible = Widget:new{}

function TestGrid:paintTo(bb)
    v_line = math.floor(bb:getWidth() / 50)
    h_line = math.floor(bb:getHeight() / 50)
    for i=1,h_line do
        y_num = i*50
        RenderText:renderUtf8Text(bb, 0, y_num+10, Font:getFace("ffont", 12), y_num, true)
        bb:paintRect(0, y_num, bb:getWidth(), 1, Blitbuffer.gray(0.7))
    end
    for i=1,v_line do
        x_num = i*50
        RenderText:renderUtf8Text(bb, x_num, 10, Font:getFace("ffont", 12), x_num, true)
        bb:paintRect(x_num, 0, 1, bb:getHeight(), Blitbuffer.gray(0.7))
    end
end

function TestVisible:paintTo(bb)
    -- Draw three lines at the borders to assess what the maximum visible coordinates are
    v_line = math.floor(bb:getWidth() / 50)
    h_line = math.floor(bb:getHeight() / 50)
    -- Paint white background for higher contrast
    bb:paintRect(0,0,bb:getWidth(),bb:getHeight(), Blitbuffer.COLOR_WHITE)
    -- Only render gridtext not lines at a more central position, so it doesn't interfere with the
    for i=1,h_line do
        y_num = i*50
        RenderText:renderUtf8Text(bb, 40, y_num+10, Font:getFace("ffont", 12), y_num, true)
    end
    for i=1,v_line do
        x_num = i*50
        RenderText:renderUtf8Text(bb, x_num, 40, Font:getFace("ffont", 12), x_num, true)
    end

    -- Handtunable minimal and maximal visible coordinates
    local x_min = 0 + 4
    local x_max = bb:getWidth() - 4
    local y_min = 0 + 3
    local y_max = bb:getHeight() - 3 - 12

    -- Render extremes on screen
    RenderText:renderUtf8Text(bb, 150, 100, Font:getFace("ffont", 22), "x_min = "..x_min, true)
    RenderText:renderUtf8Text(bb, 500, 100, Font:getFace("ffont", 22), "x_max = "..x_max, true)
    RenderText:renderUtf8Text(bb, 100, 150, Font:getFace("ffont", 22), "y_min = "..y_min, true)
    RenderText:renderUtf8Text(bb, 100, 300, Font:getFace("ffont", 22), "y_max = "..y_max, true)
    RenderText:renderUtf8Text(bb, 100, 500, Font:getFace("ffont", 26), "Visible screen size :  "..(x_max-x_min).."x"..(y_max-y_min), true)

    -- Three parallel lines at the top
    bb:paintRect(x_min,y_min, x_max, 1 , Blitbuffer.gray(0.7))
    bb:paintRect(x_min,y_min + 3, x_max, 1 , Blitbuffer.gray(0.7))
    bb:paintRect(x_min,y_min + 6, x_max, 1 , Blitbuffer.gray(0.7))

    -- Three parallel lines at the bottom
    bb:paintRect(x_min,y_max, x_max, 1 , Blitbuffer.gray(0.7))
    bb:paintRect(x_min,y_max - 3, x_max, 1 , Blitbuffer.gray(0.7))
    bb:paintRect(x_min,y_max - 6, x_max, 1 , Blitbuffer.gray(0.7))

    -- Three parallel lines at the left
    bb:paintRect(x_min,y_min, 1, y_max , Blitbuffer.gray(0.7))
    bb:paintRect(x_min + 3,y_min, 1, y_max, Blitbuffer.gray(0.7))
    bb:paintRect(x_min + 6,y_min, 1, y_max, Blitbuffer.gray(0.7))

    -- Three parallel lines at the right
    bb:paintRect(x_max,y_min, 1, y_max , Blitbuffer.gray(0.7))
    bb:paintRect(x_max - 3,y_min, 1, y_max, Blitbuffer.gray(0.7))
    bb:paintRect(x_max - 6,y_min, 1, y_max, Blitbuffer.gray(0.7))

    --Two lines spaces 600 pixels
    bb:paintRect(100,600, 1, 250 , Blitbuffer.gray(0.7))
    bb:paintRect(700,600, 1, 250 , Blitbuffer.gray(0.7))
    RenderText:renderUtf8Text(bb, 150, 670, Font:getFace("ffont", 26), "Measure inches per 600 pixels", true)
    RenderText:renderUtf8Text(bb, 150, 770, Font:getFace("ffont", 22), "Kobo Aura: 600 pixels/ 2.82 \" = "..(600/2.82).." dpi", true)
end

-----------------------------------------------------
-- we create a widget that paints a background:
-----------------------------------------------------
Background = InputContainer:new{
    is_always_active = true, -- receive events when other dialogs are active
    key_events = {
        OpenDialog = { { "Press" } },
        OpenConfirmBox = { { "Del" } },
        QuitApplication = { { { "Home", "Back" } } },
    },
    -- contains a gray rectangular desktop
    FrameContainer:new{
        background = Blitbuffer.COLOR_DARK_GRAY,
        bordersize = 0,
        dimen = Screen:getSize(),
        Widget:new{
            dimen = Geom:new{
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
        },
    }
}

function Background:onOpenDialog()
    UIManager:show(InfoMessage:new{
        text = "Example message.",
        timeout = 10
    })
end

function Background:onOpenConfirmBox()
    UIManager:show(ConfirmBox:new{
        text = "Please confirm delete"
    })
end

function Background:onInputError()
    UIManager:quit()
end

function Background:onQuitApplication()
    UIManager:quit()
end

-----------------------------------------------------
-- example widget: a clock
-----------------------------------------------------
Clock = AlphaContainer:new{
    alpha = 0.7,

    FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Screen:scaleBySize(1),
        margin = 0,
        padding = Screen:scaleBySize(1),
    }
}

function Clock:schedFunc()
    self[1][1]:free()
    self[1][1] = self:getTextWidget()
    UIManager:setDirty(self)
    -- TODO: wait until next real second shift
    UIManager:scheduleIn(1, function() self:schedFunc() end)
end

function Clock:onShow()
    self[1][1] = self:getTextWidget()
    self:schedFunc()
end

function Clock:getTextWidget()
    return CenterContainer:new{
        dimen = { w = 300, h = 25 },
        TextWidget:new{
            text = os.date("%H:%M:%S"),
            face = Font:getFace("cfont", 12)
        }
    }
end

-----------------------------------------------------
-- a confirmbox box widget
-----------------------------------------------------
Quiz = ConfirmBox:new{
    text = "Tell me the truth, isn't it COOL?!",
    width = Screen:scaleBySize(300),
    ok_text = "Yes, of course.",
    cancel_text = "No, it's ugly.",
    cancel_callback = function()
        UIManager:show(InfoMessage:new{
            text="You liar!",
        })
    end,
}

-----------------------------------------------------
-- a menu widget
-----------------------------------------------------
menu_items = {
    {text = "item1"},
    {text = "item2"},
    {text = "This is a very very log item whose length should exceed the width of the menu."},
    {text = "item3"},
    {text = "item4"},
    {text = "item5"},
    {text = "item6"},
    {text = "item7"},
    {text = "item8"},
    {text = "item9"},
    {text = "item10"},
    {text = "item11"},
    {text = "item12"},
    {text = "item13"},
    {text = "item14"},
    {text = "item15"},
    {text = "item16"},
    {text = "item17"},
}
M = Menu:new{
    title = "Test Menu",
    item_table = menu_items,
    width = Screen:scaleBySize(500),
    height = Screen:scaleBySize(600),
}

-----------------------------------------------------
-- a reader view widget
-----------------------------------------------------
readerwindow = CenterContainer:new{
    dimen = Screen:getSize(),
    FrameContainer:new{
        background = Blitbuffer.COLOR_BLACK,
    }
}
reader = ReaderUI:new{
    dialog = readerwindow,
    dimen = Geom:new{ w = Screen:getWidth() - 100, h = Screen:getHeight() - 100 },
    document = DocumentRegistry:openDocument("spec/front/unit/data/2col.pdf")
    --document = DocumentRegistry:openDocument("spec/front/unit/data/djvu3spec.djvu")
}
readerwindow[1][1] = reader


touch_menu = TouchMenu:new{
    title = "Document menu",
    width = Screen:getWidth(),
    tab_item_table = {
        {
            icon = "appbar.pokeball",
            {
                text = "item1",
                callback = function() end,
            },
            {
                text = "item2",
                callback = function() end,
            },
            {
                text = "item3",
                callback = function() end,
            },
            {
                text = "item4",
                callback = function() end,
            },
            {
                text = "item5",
                callback = function() end,
            },
            {
                text = "item6",
                callback = function() end,
            },
            {
                text = "item7",
                callback = function() end,
            },
            {
                text = "item8",
                callback = function() end,
            },
            {
                text = "item9",
                callback = function() end,
            },
        },
        {
            icon = "appbar.page.corner.bookmark",
            {
                text = "item10",
                callback = function() end,
            },
            {
                text = "item11",
                callback = function() end,
            },
        },
        {
            icon = "home",
            callback = function() DEBUG("hello world!") end
        }
    },
}

-----------------------------------------------------
-- input box widget
-----------------------------------------------------
local TestInputText = InputText:new{
    width = Screen:scaleBySize(400),
    enter_callback = function() print("Entered") end,
    scroll = false,
    input_type = "number",
    parent = {
        onSwitchFocus = false,
    },
}

-----------------------------------------------------
-- key value page
-----------------------------------------------------
function testKeyValuePage()
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local kvp = KeyValuePage:new{
        title = 'Statistics This is a very very log item whose length should exceed the width of the men',
        kv_pairs = {
            {"1 Current period", "00:00:00"},
            {"This is a very very log item whose length should exceed the width of the menu.", "value"},
            {"2 Time to read", "00:00:00 00:00:00 00:00:00 00:00:00"},
            {"2 Time to read", "00:00:00"},
            {"3 Time to read", "00:00:00"},
            {"4 Time to read", "00:00:00"},
            {"5 Time to read", "00:00:00"},
            {"6 Time to read", "00:00:00"},
            {"7 Time to read", "00:00:00"},
            {"8 Time to read", "00:00:00"},
            {"9 Time to read", "00:00:00"},
            {"10 Time to read", "00:00:00"},
            {"11 Time to read", "00:00:00"},
            "----------------------------",
            {"12 Time to read", "00:00:00"},
            {"13 Time to read", "00:00:00"},
            {"14 Time to read", "00:00:00"},
            {"15 Time to read", "00:00:00"},
            {"16 Time to read", "00:00:00"},
            {"17 Time to read", "00:00:00"},
            {"18 Time to read", "00:00:00"},
            {"19 Time to read", "00:00:00"},
            {"20 Time to read", "00:00:00"},
            {"21 Time to read", "00:00:00"},
        },
    }
    UIManager:show(kvp)
end

function testBookStatus()
    -- doc = DocumentRegistry:openDocument("spec/front/unit/data/juliet.epub")
    doc = DocumentRegistry:openDocument("spec/front/unit/data/2col.pdf")
    reader = ReaderUI:new{
        dialog = readerwindow,
        dimen = Geom:new{ w = Screen:getWidth() - 100, h = Screen:getHeight() - 100 },
        document = doc
    }

    local status_page = require("ui/widget/bookstatuswidget"):new{
        ui = reader,
    }
    UIManager:show(status_page)
end

function testTouchProbe()
    local TouchProbe = require("tools/kobo_touch_probe")
    UIManager:show(TouchProbe:new{})
end

function testNetworkSetting()
    local list = {
        {
            ssid = "CMU-SECURE",
            signal_level = -58,
            flags = "[WPA2-PSK-CCMP][ESS]",
            signal_quality = 84,
        },
        {
            ssid = "CMU-SECURE 2",
            signal_level = -258,
            signal_quality = 44,
            flags = "[WPA2-PSK-CCMP][ESS]",
            password = "okgo",
        },
        {
            ssid = "218",
            signal_level = 58,
            signal_quality = 100,
            flags = "[WEP][ESS]",
        },
        {
            ssid = "318",
            signal_level = 100,
            signal_quality = 100,
            flags = "[WPA2-PSK-CCMP][ESS]",
        },
    }

    for i=1,10 do
        table.insert(list, {
            ssid = "918-"..tostring(i),
            signal_level = -58-i*2,
            signal_quality = 84-i*2,
            flags = "[WPA2-PSK-CCMP][ESS]",
        })
    end

    local nw = require("ui/widget/networksetting"):new{network_list = list}
    UIManager:show(nw)
end


-----------------------------------------------------------------------
-- you may want to uncomment following show calls to see the changes
-----------------------------------------------------------------------
--UIManager:show(Background:new())
--UIManager:show(TestGrid)
UIManager:show(TestVisible)
UIManager:show(Clock:new())
-- UIManager:show(M)
--UIManager:show(Quiz)
--UIManager:show(readerwindow)
--UIManager:show(touch_menu)
--UIManager:show(keyboard)
--UIManager:show(TestInputText)
--TestInputText:onShowKeyboard()
-- testKeyValuePage()
-- testTouchProbe()
-- testBookStatus()
testNetworkSetting()
UIManager:run()
