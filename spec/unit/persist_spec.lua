describe("Persist module", function()
    local Persist
    local bitserInstance, dumpInstance
    local ser, deser, str
    local sample_ok = {
        a = true,
        b = nil,
        c = "something",
        d = 1234,
        e = {
            things = {
                id = 0,
                menu = nil,
            },
        },
    }
    local sample_fail = {
        a = function()
            return true
        end,
    }

    local function sameType(t1, t2)
        local msg = "wrong type (expected table)"
        assert(type(t1) == "table", msg)
        assert(type(t2) == "table", msg)
        for k, v in pairs(t1) do
            if type(v) ~= type(t2[k]) then
                return false
            end
        end
        return true
    end

    setup(function()
        require("commonrequire")
        Persist = require("persist")
        bitserInstance = Persist:new{ path = "test.dat", codec = "bitser" }
        dumpInstance = Persist:new { path = "test.txt", codec = "dump" }
    end)

    it ("should fail to serialize functions", function()
        assert.is_nil(bitserInstance:save(sample_fail))
        -- dump never fails, as it skip functions
        assert.is_true(dumpInstance:save(sample_fail))
    end)

    it("should save a table to file", function()
        assert.is_true(bitserInstance:save(sample_ok))
        assert.is_true(dumpInstance:save(sample_ok))
    end)

    it("should generate a valid file", function()
        assert.is_true(bitserInstance:exists())
        assert.is_true(bitserInstance:size() > 0)
        assert.is_true(type(bitserInstance:timestamp()) == "number")
    end)

    it("should load a table from file", function()
        assert.is_true(sameType(bitserInstance:load(), sample_ok))
        assert.is_true(sameType(dumpInstance:load(), sample_ok))
    end)

    it("should delete the file", function()
        bitserInstance:delete()
        dumpInstance:delete()
        assert.is_nil(bitserInstance:exists())
        assert.is_nil(dumpInstance:exists())
    end)

    it("should work as a standalone serializer/deserializer", function()
        for _, codec in ipairs({"dump", "bitser"}) do
            assert.is_true(Persist.getCodec(codec).id == codec)
            ser = Persist.getCodec(codec).serialize
            deser = Persist.getCodec(codec).deserialize
            str = ser(sample_ok)
            assert.is_true(sameType(deser(str), sample_ok))
            str, ser, deser = nil, nil, nil
        end
    end)
end)
