require("commonrequire")
local lfs = require("libs/libkoreader-lfs")
local NickelConf = require("device/kobo/nickel_conf")

describe("Nickel configuation module", function()
    describe("Frontlight module", function()
        it("should read value", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=55
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            assert.Equals(NickelConf.frontLightLevel.get(), 55)

            os.remove(fn)
        end)

        it("should create section", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
FrontLightLevel=6
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(100)

            fd = io.open(fn, "r")
            assert.Equals(fd:read("*a"), [[
[OtherThing]
FrontLightLevel=6
[PowerOptions]
FrontLightLevel=100
]])
            fd:close()
            os.remove(fn)

            fd = io.open(fn, "w")
            fd:write("")
            fd:close()

            NickelConf.frontLightLevel.set(20)

            fd = io.open(fn, "r")
            assert.Equals(fd:read("*a"), [[
[PowerOptions]
FrontLightLevel=20
]])
            fd:close()
            os.remove(fn)
        end)

        it("should replace value", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=6
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(100)

            fd = io.open(fn, "r")
            assert.Equals(fd:read("*a"), [[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=100
[YetAnotherThing]
bar=baz
]])
            fd:close()
            os.remove(fn)
        end)

        it("should insert entry", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[PowerOptions]
foo=bar
[OtherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(1)

            fd = io.open(fn, "r")
            assert.Equals(fd:read("*a"), [[
[PowerOptions]
foo=bar
FrontLightLevel=1
[OtherThing]
bar=baz
]])
            fd:close()
            os.remove(fn)
        end)

        it("should create config file", function()
            local fn = "/tmp/abcfoobarbaz449"
            assert.is_not.Equals(lfs.attributes(fn, "mode"), "file")
            finally(function() os.remove(fn) end)

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(15)

            fd = io.open(fn, "r")
            assert.Equals([[
[PowerOptions]
FrontLightLevel=15
]],
                          fd:read("*a"))
            fd:close()
        end)
    end)
end)
