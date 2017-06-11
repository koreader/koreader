describe("Math module", function()

    setup(function()
        require("commonrequire")
        Math = require("optmath")
    end)

    it("should round away from zero", function()
        local num = 1.5
        assert.are.same(2, Math.roundAwayFromZero(num))
        num = 1.4
        assert.are.same(2, Math.roundAwayFromZero(num))
        num = -1.4
        assert.are.same(-2, Math.roundAwayFromZero(num))
        num = 0.2
        assert.are.same(1, Math.roundAwayFromZero(num))
        num = -0.2
        assert.are.same(-1, Math.roundAwayFromZero(num))
    end)
    it("should round", function()
        local num = 1.5
        assert.are.same(2, Math.round(num))
        num = 1.4
        assert.are.same(1, Math.round(num))
        num = -1.4
        assert.are.same(-1, Math.round(num))
        num = 0.2
        assert.are.same(0, Math.round(num))
        num = -0.2
        assert.are.same(0, Math.round(num))
    end)
    it("should determine odd or even", function()
        local num = 1
        assert.are.same("odd", Math.oddEven(num))
        num = 2
        assert.are.same("even", Math.oddEven(num))
        num = 3
        assert.are.same("odd", Math.oddEven(num))
        num = 4
        assert.are.same("even", Math.oddEven(num))
        num = -4
        assert.are.same("even", Math.oddEven(num))
        num = -3
        assert.are.same("odd", Math.oddEven(num))
        num = 0
        assert.are.same("even", Math.oddEven(num))
    end)

end)
