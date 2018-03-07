describe("InputText widget module", function()
    local InputText
    setup(function()
        require("commonrequire")
        InputText = require("ui/widget/inputtext")
    end)

    describe("addChar()", function()
        -- thanks to https://stackoverflow.com/a/32660766/2470572
        local function equals(o1, o2, ignore_mt)
            if o1 == o2 then return true end
            local o1Type = type(o1)
            local o2Type = type(o2)
            if o1Type ~= o2Type then return false end
            if o1Type ~= 'table' then return false end

            if not ignore_mt then
                local mt1 = getmetatable(o1)
                if mt1 and mt1.__eq then
                    --compare using built in method
                    return o1 == o2
                end
            end

            local keySet = {}

            for key1, value1 in pairs(o1) do
                local value2 = o2[key1]
                if value2 == nil or equals(value1, value2, ignore_mt) == false then
                    return false
                end
                keySet[key1] = true
            end

            for key2, _ in pairs(o2) do
                if not keySet[key2] then return false end
            end
            return true
        end

        it("should add regular text", function()
            InputText:initTextBox("")
            InputText:addChar("a")
            assert.is_true( equals({"a"}, InputText.charlist) )
            InputText:addChar("aa")
            assert.is_true( equals({"a", "a", "a"}, InputText.charlist) )
        end)
        it("should add unicode text", function()
            InputText:initTextBox("")
            InputText:addChar("Л")
            assert.is_true( equals({"Л"}, InputText.charlist) )
            InputText:addChar("Луа")
            assert.is_true( equals({"Л", "Л", "у", "а"}, InputText.charlist) )
        end)
    end)

end)
