describe("Persist module", function()
    local Persist
    local sample
    local datadir
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
        sample = arrayOf(1000)
        datadir = require("datastorage"):getDataDir()
    end)

    for _, codec in ipairs({"dump", "serpent", "bitser", "luajit", "zstd"}) do
        it("should save/reload a table to/from file with "..codec, function()
            -- save table to file
            local instance = Persist:new{ path = datadir .. "/test_" .. codec .. ".dat", codec = codec }
            assert.is_true(instance:save(sample))
            -- check file is valid
            assert.is_true(instance:exists())
            assert.is_true(instance:size() > 0)
            assert.is_true(type(instance:timestamp()) == "number")
            -- load back table from file
            assert.are.same(sample, instance:load())
            -- delete file
            instance:delete()
            assert.is_nil(instance:exists())
        end)
    end

    for _, codec in ipairs({"dump", "serpent", "bitser", "luajit", "zstd"}) do
        it("should return standalone serializers/deserializers with "..codec, function()
            local tab = sample
            assert.is_true(Persist.getCodec(codec).id == codec)
            local ser = Persist.getCodec(codec).serialize
            local deser = Persist.getCodec(codec).deserialize
            local str = ser(tab)
            local t, err = deser(str)
            if not t then
                print(codec, "deser failed:", err)
            end
            assert.are.same(tab, t)
        end)
    end

    for _, codec in ipairs({"bitser", "luajit"}) do
        local tab = arrayOf(10000)
        it("should handle huge tables with "..codec, function()
            local ser = Persist.getCodec(codec).serialize
            local deser = Persist.getCodec(codec).deserialize
            local str = ser(tab)
            assert.are.same(tab, deser(str))
        end)
    end

    for _, codec in ipairs({"bitser", "luajit", "zstd"}) do
        it("should fail to serialize functions with "..codec, function()
            assert.is_true(Persist.getCodec(codec).id == codec)
            local ser = Persist.getCodec(codec).serialize
            local str, err = ser(fail)
            assert.is_nil(str)
            assert.is_not_nil(err)
        end)
    end

    -- The "dump" and "serpent" codecs will actually happily "serialize"
    -- functions (`tostring(func)`), and of course fail to deserialize
    -- the resulting string back…
    for _, codec in ipairs({"dump", "serpent"}) do
        it("should fail to serialize functions with "..codec, function()
            assert.is_true(Persist.getCodec(codec).id == codec)
            local ser = Persist.getCodec(codec).serialize
            local deser = Persist.getCodec(codec).deserialize
            local str = ser(fail)
            assert.is_not_nil(str)
            assert.is_nil(deser(str))
        end)
    end

end)
