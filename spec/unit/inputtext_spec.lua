describe("InputText widget module", function()
    local InputText
    local equals
    setup(function()
        require("commonrequire")
        InputText = require("ui/widget/inputtext"):new{}

        equals = require("util").tableEquals
    end)

    describe("addChars()", function()
        it("should add regular text", function()
            InputText:initTextBox("")
            InputText:addChars("a")
            assert.is_true( equals({"a"}, InputText.charlist) )
            InputText:addChars("aa")
            assert.is_true( equals({"a", "a", "a"}, InputText.charlist) )
        end)
        it("should add unicode text", function()
            InputText:initTextBox("")
            InputText:addChars("Л")
            assert.is_true( equals({"Л"}, InputText.charlist) )
            InputText:addChars("Луа")
            assert.is_true( equals({"Л", "Л", "у", "а"}, InputText.charlist) )
        end)
    end)

    describe("onKeyPress() physical keyboard", function()
        local Device, Key
        local orig_isSDL

        setup(function()
            Device = require("device")
            Key = require("device/key")
        end)

        before_each(function()
            -- The single-char insert path is skipped on SDL (the emulator gets
            -- pre-composed text via TextInput), so pretend we're not SDL here.
            orig_isSDL = Device.isSDL
            Device.isSDL = function() return false end
            InputText.focused = true
            InputText:initTextBox("")
        end)

        after_each(function()
            Device.isSDL = orig_isSDL
            InputText.focused = false
        end)

        it("should insert shifted symbols for the number row", function()
            InputText:onKeyPress(Key:new("1", {Shift = true}))
            InputText:onKeyPress(Key:new("2", {Shift = true}))
            InputText:onKeyPress(Key:new("0", {Shift = true}))
            assert.is_true( equals({"!", "@", ")"}, InputText.charlist) )
        end)

        it("should insert shifted symbols for punctuation keys", function()
            InputText:onKeyPress(Key:new(";", {Shift = true}))
            InputText:onKeyPress(Key:new("'", {Shift = true}))
            InputText:onKeyPress(Key:new("/", {Shift = true}))
            assert.is_true( equals({":", '"', "?"}, InputText.charlist) )
        end)

        it("should insert the base character without Shift", function()
            InputText:onKeyPress(Key:new(";", {}))
            InputText:onKeyPress(Key:new("1", {}))
            assert.is_true( equals({";", "1"}, InputText.charlist) )
        end)

        it("should keep letter case behavior", function()
            InputText:onKeyPress(Key:new("Q", {}))
            InputText:onKeyPress(Key:new("Q", {Shift = true}))
            assert.is_true( equals({"q", "Q"}, InputText.charlist) )
        end)
    end)
end)
