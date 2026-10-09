local IME = require("ui/data/keyboardlayouts/generic_ime")
local util = require("util")

describe("Generic IME", function()
    local function newInputBox()
        local chars = {}
        return {
            addChars = {
                raw_method_call = function(_, value)
                    util.arrayAppend(chars, util.splitToChars(value))
                end,
            },
            delChar = {
                raw_method_call = function()
                    table.remove(chars)
                end,
            },
            getText = function()
                return table.concat(chars)
            end,
        }
    end

    it("reports and selects candidates", function()
        local reported_candidates = {}
        local reported_index
        local ime = IME:new{
            code_map = {
                n = { "你", "拟" },
                ni = { "你", "拟", "尼" },
            },
            show_candi_callback = function() return false end,
            candidate_callback = function(_, candidates, index)
                reported_candidates = candidates
                reported_index = index
            end,
        }
        local inputbox = newInputBox()

        ime:wrappedAddChars(inputbox, "n")
        ime:wrappedAddChars(inputbox, "i")

        assert.are.equal("你", inputbox.getText())
        assert.are.same({ "你", "拟", "尼" }, reported_candidates)
        ime:wrappedAddChars(inputbox, "SWITCH")
        assert.are.equal("拟", inputbox.getText())
        assert.are.equal(2, reported_index)
        assert.is_true(ime:selectCandidate(inputbox, 3))
        assert.are.equal("尼", inputbox.getText())
        assert.are.same({}, reported_candidates)
    end)
end)
