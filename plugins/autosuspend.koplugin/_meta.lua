local _ = require("gettext")
return {
    name = "autosuspend",
    fullname = _("Auto suspend"),
    description = _([["Puts the device into sleep mode (standby, suspend, power off) after specified periods of inactivity."]]),
}
