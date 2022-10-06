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
end)
