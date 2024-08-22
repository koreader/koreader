-- ButtonDialogTitle widget is deprecated.
-- Use ButtonDialog instead.

local logger = require("logger")
logger.warn("Calling deprecated ButtonDialogTitle widget")
return require("ui/widget/buttondialog")
