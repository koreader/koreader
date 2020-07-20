describe("Menu widget", function()
    local Menu
    setup(function()
        require("commonrequire")
        Menu = require("ui/widget/menu")
    end)

    it("should convert item table from touch menu properly", function()
        local cb1 = function() end
        local cb2 = function() end
        local re = Menu.itemTableFromTouchMenu({
            navi = {
                icon = 'foo/bar.png',
                { text = 'foo', callback = cb1 },
                { text = 'bar', callback = cb2 },
            },
            exit = {
                icon = 'foo/bar2.png',
                callback = cb2
            },
        })
        --- @fixme: Currently broken because pairs (c.f., https://github.com/koreader/koreader/pull/6371#issuecomment-657251302)
        assert.are.same({
            {
                text = 'exit',
                callback = cb2,
            },
            {
                text = 'navi',
                sub_item_table = {
                    icon = 'foo/bar.png',
                    { text = 'foo', callback = cb1 },
                    { text = 'bar', callback = cb2 },
                }
            },
        }, re)
    end)
end)
