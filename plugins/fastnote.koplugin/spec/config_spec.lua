-- spec/config_spec.lua
--
-- Unit tests for lib/config.lua.
-- Pure Lua — no KOReader runtime needed.

describe("lib/config", function()

    local Config

    -- Path to a temp file we can write test config content into.
    local function write_tmp(content)
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write(content)
        f:close()
        return path
    end

    before_each(function()
        -- Reload the module each test so state does not bleed.
        package.loaded["lib/config"] = nil
        Config = require("lib/config")
    end)

    -- DEFAULTS ---------------------------------------------------------------

    it("exposes DEFAULTS table with finger_draw = false", function()
        assert.is_table(Config.DEFAULTS)
        assert.is_false(Config.DEFAULTS.finger_draw)
    end)

    it("exposes DEFAULTS table with rotation_mode = 'auto'", function()
        assert.is_table(Config.DEFAULTS)
        assert.are.equal("auto", Config.DEFAULTS.rotation_mode)
    end)

    it("reads rotation_mode as a number from a valid config file", function()
        local path = write_tmp("return { rotation_mode = 3 }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal(3, cfg.rotation_mode)
    end)

    it("uses default rotation_mode when absent from config file", function()
        local path = write_tmp("return { finger_draw = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal("auto", cfg.rotation_mode)
    end)

    -- NIL / MISSING PATH -----------------------------------------------------

    it("returns defaults when path is nil", function()
        local cfg = Config.load(nil)
        assert.is_false(cfg.finger_draw)
    end)

    it("returns defaults when file does not exist", function()
        local cfg = Config.load("/nonexistent/definitely/missing/fastnote.conf")
        assert.is_false(cfg.finger_draw)
    end)

    -- VALID CONFIG FILES -----------------------------------------------------

    it("reads finger_draw = true from a valid config file", function()
        local path = write_tmp("return { finger_draw = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_true(cfg.finger_draw)
    end)

    it("reads finger_draw = false from a valid config file", function()
        local path = write_tmp("return { finger_draw = false }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.finger_draw)
    end)

    it("merges defaults for keys absent from the config file", function()
        -- Empty table → all keys come from DEFAULTS
        local path = write_tmp("return {}")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.finger_draw)
    end)

    -- MALFORMED / UNEXPECTED FILES -------------------------------------------

    it("returns defaults when file has a syntax error", function()
        local path = write_tmp("this is not valid lua !!!!")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.finger_draw)
    end)

    it("returns defaults when file does not return a table", function()
        local path = write_tmp("return 42")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.finger_draw)
    end)

    it("returns defaults when file returns nil", function()
        local path = write_tmp("return nil")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.finger_draw)
    end)

    -- MUTATION SAFETY --------------------------------------------------------

    it("mutating the returned table does not affect DEFAULTS", function()
        local cfg = Config.load(nil)
        cfg.finger_draw = true
        assert.is_false(Config.DEFAULTS.finger_draw)
    end)

end)
