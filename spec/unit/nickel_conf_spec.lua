describe("Nickel configuation module", function()
    local lfs, NickelConf
    setup(function()
        require("commonrequire")
        lfs = require("libs/libkoreader-lfs")
        NickelConf = require("device/kobo/nickel_conf")
    end)

    describe("Frontlight module", function()
        it("should read value", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=55
FrontLightState=true
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            assert.Equals(NickelConf.frontLightLevel.get(), 55)
            assert.Equals(NickelConf.frontLightState.get(), true)

            os.remove(fn)
        end)

        it("should also read value", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=30
FrontLightState=false
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            assert.Equals(NickelConf.frontLightLevel.get(), 30)
            assert.Equals(NickelConf.frontLightState.get(), false)

            os.remove(fn)
        end)

        it("should have default value", function()
            local fn = os.tmpname()
            local fd = io.open(fn, "w")
            fd:write([[
[OtherThing]
foo=bar
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            assert.Equals(NickelConf.frontLightLevel.get(), 1)
            assert.Equals(NickelConf.frontLightState.get(), nil)

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
            NickelConf.frontLightState.set(true)

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
            NickelConf.frontLightState.set(false)

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
FrontLightState=false
[YetAnotherThing]
bar=baz
]])
            fd:close()

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(100)
            NickelConf.frontLightState.set(true)

            fd = io.open(fn, "r")
            assert.Equals(fd:read("*a"), [[
[OtherThing]
foo=bar
[PowerOptions]
FrontLightLevel=100
FrontLightState=true
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
            NickelConf.frontLightState.set(true)

            fd = io.open(fn, "r")
            assert.Equals([[
[PowerOptions]
foo=bar
FrontLightLevel=1
[OtherThing]
bar=baz
]], fd:read("*a"))
            fd:close()
            os.remove(fn)
        end)

        it("should create config file", function()
            local fn = "/tmp/abcfoobarbaz449"
            assert.is_not.Equals(lfs.attributes(fn, "mode"), "file")
            finally(function() os.remove(fn) end)

            NickelConf._set_kobo_conf_path(fn)
            NickelConf.frontLightLevel.set(15)
            NickelConf.frontLightState.set(false)

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
