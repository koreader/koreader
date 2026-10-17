-- Page-turn animation ("water ripple") for the iReader Neo 3 Ultra.
-- The effect is stored as the per-document configurable `page_turn_effect`, so
-- "Save document settings as default" and "Reset" handle it like any other
-- option.

local Device = require("device")
local _ = require("gettext")

local PageTurnEffect = {
    KEY = "page_turn_effect",
    DEFAULT = "ripple_standard",
    OPTIONS = {
        { id = "none",             text = _("No animation") },
        { id = "ripple_slow",      text = _("Water ripple – slow") },
        { id = "ripple_standard",  text = _("Water ripple – standard") },
        { id = "ripple_fast",      text = _("Water ripple – fast") },
    },
}

function PageTurnEffect.enabled()
    return Device:hasPageTurnAnimation()
end

function PageTurnEffect.resolve(ui)
    local configurable = ui and ui.document and ui.document.configurable
    if not configurable then
        return PageTurnEffect.DEFAULT
    end
    -- Configurable stores option values under bare keys ("page_turn_effect");
    -- it only prefixes them ("copt_"/"kopt_") when (de)serializing to settings.
    return configurable[PageTurnEffect.KEY] or PageTurnEffect.DEFAULT
end

function PageTurnEffect.set(ui, id)
    local configurable = ui and ui.document and ui.document.configurable
    if not configurable then
        return
    end
    configurable[PageTurnEffect.KEY] = id
    if ui.doc_settings then
        local prefix = ui.document.koptinterface and "kopt_" or "copt_"
        ui.doc_settings:saveSetting(prefix .. PageTurnEffect.KEY, id)
        ui.doc_settings:flush()
    end
end

return PageTurnEffect
