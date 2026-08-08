describe("LanguageSupport module", function()
    local LanguageSupport

    setup(function()
        require("commonrequire")
        LanguageSupport = require("languagesupport")
    end)

    local instance

    before_each(function()
        -- The plugin list is a singleton shared by every instance, so a leftover
        -- plugin from a previous test would be found by the one after it.
        for name in pairs(LanguageSupport.plugins) do
            LanguageSupport.plugins[name] = nil
        end
        instance = LanguageSupport:new{ ui = { doc_props = {} } }
    end)

    -- A plugin that claims the language matching its own name, and answers a
    -- word lookup with whatever the handler returns.
    local function makePlugin(name, onWordLookup)
        return {
            name = name,
            supportsLanguage = function(_, language_code) return language_code == name end,
            onWordLookup = onWordLookup,
        }
    end

    local function lookup(language_code, text)
        instance.ui.doc_props.language = language_code
        return instance:extraDictionaryFormCandidates(text)
    end

    describe("extraDictionaryFormCandidates()", function()
        it("should use the plugin matching the document language", function()
            instance:registerPlugin(makePlugin("kk", function() return { "kk-candidate" } end))
            instance:registerPlugin(makePlugin("ja", function() return { "ja-candidate" } end))
            assert.are.same({ "kk-candidate" }, lookup("kk", "word"))
            assert.are.same({ "ja-candidate" }, lookup("ja", "word"))
        end)

        it("should fall back to every other plugin when no plugin claims the language", function()
            instance:registerPlugin(makePlugin("kk", function() return { "kk-candidate" } end))
            assert.are.same({ "kk-candidate" }, lookup("ru", "word"))
        end)

        it("should go on to the next plugin when one declines the text", function()
            -- Returning nothing means "this is not my text". The search must
            -- continue regardless of the order pairs() happens to visit them in.
            local declined = false
            instance:registerPlugin(makePlugin("xx", function() declined = true end))
            instance:registerPlugin(makePlugin("yy", function() return { "candidate" } end))
            assert.are.same({ "candidate" }, lookup("unknown", "word"))
            assert.is_true(declined)
        end)

        it("should go on to the next plugin when one crashes", function()
            instance:registerPlugin(makePlugin("xx", function() error("boom") end))
            instance:registerPlugin(makePlugin("yy", function() return { "candidate" } end))
            assert.are.same({ "candidate" }, lookup("unknown", "word"))
        end)

        it("should return nothing when every plugin declines", function()
            instance:registerPlugin(makePlugin("xx", function() end))
            instance:registerPlugin(makePlugin("yy", function() end))
            assert.is_nil(lookup("unknown", "word"))
        end)

        it("should return nothing when no plugins are registered", function()
            assert.is_nil(lookup("unknown", "word"))
        end)
    end)
end)
