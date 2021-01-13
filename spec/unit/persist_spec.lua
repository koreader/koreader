describe("Persist module", function()
    local Persist
    local sample
    local bitserInstance, dumpInstance
    local ser, deser, str, tab
    local fail = { a = function() end, }

    local function arrayOf(n)
        assert(type(n) == "number", "wrong type (expected number)")
        local t = {}
        for i = 1, n do
            table.insert(t, i, {
                a = "sample " .. tostring(i),
                b = true,
                c = nil,
                d = i,
                e = {
                    f = {
                        g = nil,
                        h = false,
                    },
                },
            })
        end
        return t
    end

    setup(function()
        require("commonrequire")
        Persist = require("persist")
        bitserInstance = Persist:new{ path = "test.dat", codec = "bitser" }
        dumpInstance = Persist:new { path = "test.txt", codec = "dump" }
        sample = arrayOf(1000)
    end)

    it("should save a table to file", function()
        assert.is_true(bitserInstance:save(sample))
        assert.is_true(dumpInstance:save(sample))
    end)

    it("should generate a valid file", function()
        assert.is_true(bitserInstance:exists())
        assert.is_true(bitserInstance:size() > 0)
        assert.is_true(type(bitserInstance:timestamp()) == "number")
    end)

    it("should load a table from file", function()
        assert.are.same(sample, bitserInstance:load())
        assert.are.same(sample, dumpInstance:load())
    end)

    it("should delete the file", function()
        bitserInstance:delete()
        dumpInstance:delete()
        assert.is_nil(bitserInstance:exists())
        assert.is_nil(dumpInstance:exists())
    end)

    it("should return standalone serializers/deserializers", function()
        tab = sample
        for _, codec in ipairs({"dump", "bitser"}) do
            assert.is_true(Persist.getCodec(codec).id == codec)
            ser = Persist.getCodec(codec).serialize
            deser = Persist.getCodec(codec).deserialize
            str = ser(tab)
            assert.are.same(deser(str), tab)
            str, ser, deser = nil, nil, nil
        end
    end)

    it("should work with huge tables", function()
        tab = arrayOf(100000)
        ser = Persist.getCodec("bitser").serialize
        deser = Persist.getCodec("bitser").deserialize
        str = ser(tab)
        assert.are.same(deser(str), tab)
    end)

    it ("should fail to serialize functions", function()
        for _, codec in ipairs({"dump", "bitser"}) do
            assert.is_true(Persist.getCodec(codec).id == codec)
            ser = Persist.getCodec(codec).serialize
            deser = Persist.getCodec(codec).deserialize
            str = ser(fail)
            assert.are_not.same(deser(str), fail)
        end
    end)

end)
