describe("FocusManager module", function()
    local FocusManager
    local layout, big_layout
    local Key
    local Input
    local Up = function(self) self:onFocusMove({0, -1}) end
    local Down = function(self) self:onFocusMove({0, 1}) end
    local Left = function(self) self:onFocusMove({-1, 0}) end
    local Right = function(self) self:onFocusMove({1, 0}) end
    local Next = function(self) self:onFocusNext() end
    local Previous = function(self) self:onFocusPrevious() end
    local HalfMoveUp = function(self) self:onFocusHalfMove({"up"}) end
    local HalfMoveDown = function(self) self:onFocusHalfMove({"down"}) end
    local HalfMoveLeft = function(self) self:onFocusHalfMove({"left"}) end
    local HalfMoveRight = function(self) self:onFocusHalfMove({"right"}) end
    local MoveTo = function(self, x, y) self:moveFocusTo(x, y) end
    setup(function()
        require("commonrequire")
        FocusManager = require("ui/widget/focusmanager")
        Key = require("device/key")
        Input = require("device/input")
        local Widget = require("ui/widget/textwidget")
        local w = Widget:new{}
        layout= {
                {w,  w,  w},
                {nil,w,nil},
                {nil,w,nil},
                }
        big_layout = {
            {w, w, w, w, w},
            {w, w, w, w, w},
            {w, w, w, w, w},
            {w, w, w, w, w},
            {w, w, w, w, w},
        }
    end)
    it("should go right", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Right(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should go left", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 2}
        Left(focusmanager)
        assert.are.same({y = 1,x = 1}, focusmanager.selected)
    end)
    it("should go up", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Up(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should go down", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Down(focusmanager)
        assert.are.same({y = 3,x = 2}, focusmanager.selected)
    end)
    it("should vertical wrapAround up", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Up(focusmanager)
        assert.are.same({y = 3,x = 2}, focusmanager.selected)
    end)
    it("should vertical wrapAround down", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 3,x = 2}
        Down(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should do vertical step to the right", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Down(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should do vertical step to the left", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 3}
        Down(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should respect left limit", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Left(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should respect right limit", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Right(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should move next right", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 2}
        Next(focusmanager)
        assert.are.same({y = 1,x = 3}, focusmanager.selected)
    end)
    it("should move next row at end of row", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 3}
        Next(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should move next left", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 2}
        Previous(focusmanager)
        assert.are.same({y = 1,x = 1}, focusmanager.selected)
    end)
    it("should move previous at start of row", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 3,x = 2}
        Previous(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should move half rows or columns", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = big_layout
        focusmanager.selected = {x = 1, y = 1}
        HalfMoveRight(focusmanager)
        assert.are.same({y = 1,x = 3}, focusmanager.selected)
        HalfMoveDown(focusmanager)
        assert.are.same({y = 3,x = 3}, focusmanager.selected)
        HalfMoveLeft(focusmanager)
        assert.are.same({y = 3,x = 1}, focusmanager.selected)
        HalfMoveUp(focusmanager)
        assert.are.same({y = 1,x = 1}, focusmanager.selected)
    end)
    it("should move to specified position", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = big_layout
        focusmanager.selected = {x = 1, y = 1}
        MoveTo(focusmanager, 3, 4)
        assert.are.same({y = 4,x = 3}, focusmanager.selected)
    end)
    it("should set layout to nil", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager:disableFocusManagement()
        assert.is_nil(focusmanager.layout)
    end)
    it("should merge into rows", function()
        local w = layout[1][1]
        local fm1 = FocusManager:new{}
        fm1.layout = {
            {w, w, w}
        }
        local fm2 = FocusManager:new{}
        fm2.layout = {
            {w, w},
        }
        fm1:mergeLayoutInVertical(fm2)
        local expected = {
            {w, w, w},
            {w, w}
        }
        assert.are.same(expected, fm1.layout)
    end)
    it("should merge into rows at specified position", function()
        local w = layout[1][1]
        local fm1 = FocusManager:new{}
        fm1.layout = {
            {w, w, w},
            {w, w, w},
        }
        local fm2 = FocusManager:new{}
        fm2.layout = {
            {w, w},
        }
        fm1:mergeLayoutInVertical(fm2, 2)
        local expected = {
            {w, w, w},
            {w, w},
            {w, w, w},
        }
        assert.are.same(expected, fm1.layout)
    end)
    it("should merge into columns", function()
        local w = layout[1][1]
        local fm1 = FocusManager:new{}
        fm1.layout = {
            {w},
            {w},
        }
        local fm2 = FocusManager:new{}
        fm2.layout = {
            {w, w},
            {w},
        }
        fm1:mergeLayoutInHorizontal(fm2, 2)
        local expected = {
            {w, w, w},
            {w, w},
        }
        assert.are.same(expected, fm1.layout)
    end)
    it("alternative key", function()
        local focusmanager = FocusManager:new{}
        focusmanager.extra_key_events = {
            Hold = { { "Sym", "AA" }, event="Hold" },
            HalfFocusUp = { { "Alt", "Up" }, event = "FocusHalfMove", args = {"up"} },
        }
        local m = Input.modifiers
        m.Sym = true
        assert.is_true(focusmanager:isAlternativeKey(Key:new("AA", m)))
        m.Sym = false
        m.Alt = true
        assert.is_true(focusmanager:isAlternativeKey(Key:new("Up", m)))
        m.Alt = false
        assert.is_false(focusmanager:isAlternativeKey(Key:new("AA", m)))
        assert.is_false(focusmanager:isAlternativeKey(Key:new("Up", m)))
    end)
end)
