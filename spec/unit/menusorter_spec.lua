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

        assert.is_true(test_menu[1].id == "setting")
        assert.is_true(test_menu[2].id == "tools")
        assert.is_true(test_menu[3].id == "search")
        assert.is_true(test_menu[4].id == "main")
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

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][1].sub_item_table[1].id == "third1")
        assert.is_true(test_menu[1][1].sub_item_table[2].id == "third2")
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
        assert.is_true(#test_menu[1] == 3)
        for _, menu_item in ipairs(test_menu[1]) do
            -- it should have an id
            assert.is_true(type(menu_item.id) == "string")
            -- it should have NEW: prepended
            assert.is_true(string.sub(menu_item.text,1,string.len(MenuSorter.orphaned_prefix))==MenuSorter.orphaned_prefix)
        end
    end)
    it("should not treat disabled as orphans", function()
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
            ["KOMenu:disabled"] = {"main", "search"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        -- only "tools" should be placed in the first menu
        assert.is_true(#test_menu[1] == 1)
        assert.is_true(test_menu[1][1].id == "tools")
    end)
    it("should attach separator=true to previous item", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third1 = {},
            third2 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second", "----------------------------", "third1", "----------------------------", "third2"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][1].separator == true)
        assert.is_true(test_menu[1][2].id == "third1")
        assert.is_true(test_menu[1][2].separator == true)
        assert.is_true(test_menu[1][3].id == "third2")
    end)
    it("should compress menus when items from order are missing", function()
        local menu_items = {
            ["KOMenu:menu_buttons"] = {},
            first = {},
            second = {},
            third2 = {},
            third4 = {},
        }
        local order = {
            ["KOMenu:menu_buttons"] = {"first",},
            first = {"second", "third1", "third2", "third3", "third4"},
        }

        local test_menu = MenuSorter:sort(menu_items, order)

        assert.is_true(test_menu[1].id == "first")
        assert.is_true(test_menu[1][1].id == "second")
        assert.is_true(test_menu[1][2].id == "third2")
        assert.is_true(test_menu[1][3].id == "third4")
    end)
end)
