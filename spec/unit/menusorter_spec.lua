describe("MenuSorter module", function()
    local MenuSorter
    setup(function()
        require("commonrequire")
        MenuSorter = require("ui/menusorter")
    end)

    it("should put menu items in the defined order", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {},
            search = {},
            tools = {},
            setting = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
                "tools",
                "search",
                "main",
            },
            main = {},
            search = {},
            tools = {},
            setting = {},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert(test_menu[1].id == "setting")
        assert(test_menu[2].id == "tools")
        assert(test_menu[3].id == "search")
        assert(test_menu[4].id == "main")
    end)
    it("should attach submenus correctly", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third1 = {},
            third2 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second"},
            second = {"third1", "third2"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert(test_menu[1].id == "first")
        assert(test_menu[1][1].id == "second")
        assert(test_menu[1][2][1].id == "third1")
        assert(test_menu[1][2][2].id == "third2")
    end)
    it("should put orphans in the first menu", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            main = {text="Main"},
            search = {text="Search"},
            tools = {text="Tools"},
            setting = {text="Settings"},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {
                "setting",
            },
            setting = {},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        -- all three should be in the first menu
        assert(#test_menu[1] == 3)
        for _, menu_item in ipairs(test_menu[1]) do
            -- it hsould have an id
            assert(type(menu_item.id) == "string")
            -- it should have NEW: prepended
            assert(string.sub(menu_item.text,1,string.len(MenuSorter.orphaned_prefix))==MenuSorter.orphaned_prefix)
        end
    end)
    it("should attach separator=true to previous item", function()

    end)
    it("should compress menus when items from order are missing", function()

    end)
end)
