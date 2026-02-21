local _ = require("gettext")

local meta = {
    name = "hello",
    fullname = _("Hello"),
    description = _([[This is a debugging plugin.]]),
}
if os.getenv("KODEV_INCOMPATIBLE_PLUGIN") then
    meta.compatibility = {
        min_version = "v0000.01-1",
        max_version = "v1111.09-9",
    }
end
return meta
