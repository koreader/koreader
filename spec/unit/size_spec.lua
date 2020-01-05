describe("Size module", function()
    local Size
    setup(function()
        require("commonrequire")
        Size = require("ui/size")
    end)
    describe("should get size", function()
        it("for window border", function()
            assert.is_true(Size.border.window >= 1)
        end)
    end)
    it("should be nil for non-existent property", function()
        assert.is_nil(Size.supercalifragilisticexpialidocious)
        assert.is_nil(Size.border.supercalifragilisticexpialidocious)
    end)
    it("should fail for non-existent property when debug is activated", function()
        local dbg = require("dbg")
        dbg:turnOn()
        Size = package.reload("ui/size")
        local supercalifragilisticexpialidocious1 = function()
            return Size.supercalifragilisticexpialidocious
        end
        local supercalifragilisticexpialidocious2 = function()
            return Size.border.supercalifragilisticexpialidocious
        end

        assert.has_error(supercalifragilisticexpialidocious1, "Size: this property does not exist: Size.supercalifragilisticexpialidocious")
        assert.has_error(supercalifragilisticexpialidocious2, "Size: this property does not exist: Size.border.supercalifragilisticexpialidocious")
        dbg:turnOff()
    end)
end)
