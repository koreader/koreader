local KeyboardLayout = dofile("plugins/externalkeyboard.koplugin/keyboard_layout.lua")

describe("ExternalKeyboard layout resolver (us)", function()
    local function r(name, shift)
        return KeyboardLayout.resolve("us", name, { Shift = shift or false })
    end

    it("case-folds letters", function()
        assert.are.equal("a", r("A"))
        assert.are.equal("A", r("A", true))
        assert.are.equal("z", r("Z"))
        assert.are.equal("Z", r("Z", true))
    end)

    it("passes digits through and maps shifted digits to symbols", function()
        assert.are.equal("1", r("1"))
        assert.are.equal("!", r("1", true))
        assert.are.equal("@", r("2", true))
        assert.are.equal(")", r("0", true))
    end)

    it("maps base and shifted punctuation", function()
        assert.are.equal(";", r(";"))
        assert.are.equal(":", r(";", true))
        assert.are.equal("/", r("/"))
        assert.are.equal("?", r("/", true))
        assert.are.equal("-", r("-"))
        assert.are.equal("_", r("-", true))
        assert.are.equal("[", r("["))
        assert.are.equal("{", r("[", true))
        assert.are.equal("`", r("`"))
        assert.are.equal("~", r("`", true))
        assert.are.equal('"', r("'", true))
    end)

    it("resolves space at both levels", function()
        assert.are.equal(" ", r(" "))
        assert.are.equal(" ", r(" ", true))
    end)

    it("uses an AltGr level when a layout defines one", function()
        assert.is_nil(KeyboardLayout.resolve("us", "1", { AltGr = true }))
        assert.is_nil(KeyboardLayout.resolve("us", "1", { Shift = true, AltGr = true }))
    end)

    it("uses AltGr for generated layouts", function()
        KeyboardLayout.layouts.test_altgr = {
            ["1"] = { "1", "!", "@", "#" },
        }
        assert.are.equal("@", KeyboardLayout.resolve("test_altgr", "1", { AltGr = true }))
        assert.are.equal("#", KeyboardLayout.resolve("test_altgr", "1", { Shift = true, AltGr = true }))
    end)

    it("resolves the ISO extra key", function()
        KeyboardLayout.layouts.test_lsgt = {
            ["<"] = { "<", ">" },
        }
        assert.are.equal("<", KeyboardLayout.resolve("test_lsgt", "<"))
        assert.are.equal(">", KeyboardLayout.resolve("test_lsgt", "<", { Shift = true }))
    end)

    it("composes generated dead keys", function()
        KeyboardLayout.layouts.test_dead = {
            ["'"] = { { dead = "dead_acute" } },
            ["^"] = { { dead = "dead_circumflex" } },
            ["E"] = { "e", "E" },
            ["X"] = { "x", "X" },
            [" "] = { " " },
        }
        assert.is_nil(KeyboardLayout.resolve("test_dead", "'"))
        assert.are.equal("é", KeyboardLayout.resolve("test_dead", "E"))
        assert.is_nil(KeyboardLayout.resolve("test_dead", "'"))
        assert.are.equal("\194\180", KeyboardLayout.resolve("test_dead", " "))
        assert.is_nil(KeyboardLayout.resolve("test_dead", "^"))
        assert.are.equal("x\204\130", KeyboardLayout.resolve("test_dead", "X"))
    end)

    it("does not apply a pending dead key after changing layouts", function()
        KeyboardLayout.layouts.test_dead = {
            ["'"] = { { dead = "dead_acute" } },
        }
        assert.is_nil(KeyboardLayout.resolve("test_dead", "'"))
        assert.are.equal("e", KeyboardLayout.resolve("us", "E"))
        assert.are.equal("e", KeyboardLayout.resolve("test_dead", "E"))
    end)

    it("returns nil for keys it does not handle", function()
        assert.is_nil(r("F1"))
        assert.is_nil(r("Home"))
        assert.is_nil(r("Up"))
    end)

    it("returns nil for an unknown layout", function()
        assert.is_nil(KeyboardLayout.resolve("dvorak", "1", { Shift = true }))
    end)

    it("returns nil while a shortcut modifier is held", function()
        KeyboardLayout.layouts.test_altgr_shortcuts = {
            ["E"] = { "e", "E", "€", "¢" },
        }
        assert.are.equal("€", KeyboardLayout.resolve("test_altgr_shortcuts", "E", { AltGr = true }))
        assert.are.equal("¢", KeyboardLayout.resolve("test_altgr_shortcuts", "E", { AltGr = true, Shift = true }))
        assert.is_nil(KeyboardLayout.resolve("us", "U", { Ctrl = true }))
        assert.is_nil(KeyboardLayout.resolve("us", "A", { Alt = true }))
        assert.is_nil(KeyboardLayout.resolve("us", "C", { Meta = true }))
        assert.is_nil(KeyboardLayout.resolve("us", "1", { Ctrl = true, Shift = true }))
    end)
end)
