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

    -- TIGHTEN / LIVE_COLOR_REFRESH DEFAULTS -----------------------------------

    it("exposes DEFAULTS table with tighten_delay = 2.5", function()
        assert.are.equal(2.5, Config.DEFAULTS.tighten_delay)
    end)

    it("exposes DEFAULTS table with tighten_enabled = true", function()
        assert.is_true(Config.DEFAULTS.tighten_enabled)
    end)

    it("exposes DEFAULTS table with live_color_refresh = false", function()
        assert.is_false(Config.DEFAULTS.live_color_refresh)
    end)

    it("reads tighten_delay from a valid config file", function()
        local path = write_tmp("return { tighten_delay = 1.0 }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal(1.0, cfg.tighten_delay)
    end)

    it("reads live_color_refresh = true from a valid config file", function()
        local path = write_tmp("return { live_color_refresh = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_true(cfg.live_color_refresh)
    end)

    it("uses default tighten_delay/tighten_enabled when absent from config file", function()
        local path = write_tmp("return { finger_draw = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal(2.5, cfg.tighten_delay)
        assert.is_true(cfg.tighten_enabled)
    end)

    -- AND/OR MERGE BUG REGRESSION ---------------------------------------------
    -- `out[k] = (cfg[k] ~= nil) and cfg[k] or v` would silently discard an
    -- explicit `false` and return the DEFAULTS value instead. tighten_enabled
    -- defaults to true, so it is the case that actually exercises the bug.

    it("preserves an explicit false for tighten_enabled (default is true)", function()
        local path = write_tmp("return { tighten_enabled = false }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.tighten_enabled)
    end)

    it("preserves an explicit false for debug_input_log alongside other overrides", function()
        -- debug_input_log's default is already false, but check the merge
        -- still reports it explicitly rather than by accident.
        local path = write_tmp("return { debug_input_log = false, tighten_enabled = false }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.is_false(cfg.debug_input_log)
        assert.is_false(cfg.tighten_enabled)
    end)

    -- ERASER_BUTTON -----------------------------------------------------------

    it("exposes DEFAULTS table with eraser_button = 'stylus'", function()
        assert.are.equal("stylus", Config.DEFAULTS.eraser_button)
    end)

    it("uses default eraser_button when absent from config file", function()
        local path = write_tmp("return { finger_draw = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal("stylus", cfg.eraser_button)
    end)

    it("reads eraser_button = 'stylus2' from a valid config file", function()
        local path = write_tmp("return { eraser_button = 'stylus2' }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal("stylus2", cfg.eraser_button)
    end)

    -- LIVE_INK_STYLE -----------------------------------------------------------

    it("exposes DEFAULTS table with live_ink_style = 'solid'", function()
        assert.are.equal("solid", Config.DEFAULTS.live_ink_style)
    end)

    it("uses default live_ink_style when absent from config file", function()
        local path = write_tmp("return { finger_draw = true }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal("solid", cfg.live_ink_style)
    end)

    it("reads live_ink_style = 'color' from a valid config file and it survives the merge", function()
        local path = write_tmp("return { live_ink_style = 'color' }")
        local cfg = Config.load(path)
        os.remove(path)
        assert.are.equal("color", cfg.live_ink_style)
    end)

end)
