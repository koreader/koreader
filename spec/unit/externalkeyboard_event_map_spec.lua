describe("ExternalKeyboard event_map_keyboard", function()
    local event_map = dofile("plugins/externalkeyboard.koplugin/event_map_keyboard.lua")

    it("gives the base punctuation keys their correct names", function()
        assert.are.equal("-", event_map[12])  -- KEY_MINUS
        assert.are.equal("=", event_map[13])  -- KEY_EQUAL
        assert.are.equal("[", event_map[26])  -- KEY_LEFTBRACE
        assert.are.equal("]", event_map[27])  -- KEY_RIGHTBRACE
        assert.are.equal(";", event_map[39])  -- KEY_SEMICOLON (was ":")
        assert.are.equal("`", event_map[41])  -- KEY_GRAVE
    end)
end)
