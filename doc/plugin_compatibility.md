# Plugin compatibility

## TL;DR

If a plugin sets a `compatibility` table in its `_meta.lua`, for example:

```lua
-- NOTE: the format must be vYYYY.MM(-\d+)?
meta.compatibility = {
    min_version = "v0000.01-1",
    max_version = "v1111.09-9",
}
```

the plugin loader checks whether the running KOReader version falls within the
range `[min_version, max_version]`. If it does, the plugin is loaded
normally. If it does not, the plugin is treated as *incompatible* and is
prevented from loading automatically. The user can override that decision.

You can also specify only `min_version` or only `max_version`:

- If only `min_version` is provided, the plugin is considered compatible with
  that version and any later versions.
- If only `max_version` is provided, the plugin is considered compatible with
  any version up to and including that version.
- If neither `min_version` nor `max_version` is provided, there is no
  version constraint and the plugin is assumed compatible by the version
  checker.

## User override options

 User-facing options are provided to control what happens when a plugin is
found to be incompatible. The available actions are:

- `nil` / "Ask on incompatibility (default)" — prompt the user for a decision.
- `"load-once"` — load the plugin this session only (useful for testing).
- `"always"` — always load the plugin regardless of declared compatibility.
- `"never"` — never load the plugin automatically.

These correspond to UI choices surfaced after plugin discovery. The runtime
option that enables compatibility checks is:

```lua
-- When true, KOReader validates plugin `compatibility` fields and prevents
-- automatic loading of plugins that are out of range. When false, all plugins
-- are loaded regardless of declared compatibility.
ENABLE_PLUGIN_COMPATIBILITY_CHECKS = true
```

Setting this flag to `false` in `defaults.lua` disables the
compatibility subsystem entirely and allows all plugins to load.

## When to use compatibility ranges

Declare compatibility for plugins that can break core behavior or can prevent
KOReader from starting or functioning correctly. Examples:

- Plugins that modify core reader behaviour (e.g. `readerpaging`,
  `readerrolling`) — incorrect assumptions between versions may crash the
  reader or make documents unreadable.
- Plugins that change early startup behavior (e.g. `filebrowser`) — these
  could cause crash loops or prevent the app from launching.

In these cases, setting conservative compatibility ranges prevents the plugin
from being loaded automatically on an incompatible KOReader version. More
adventurous users can still try `"load-once"` to test the plugin against the
new version; if it crashes, it won't be loaded automatically again.

## Implementation notes

The implementation lives in `frontend/plugincompatibility.lua` and the
plugin loader logic is in `frontend/pluginloader.lua`. The loader reads each
plugin's `_meta.lua` first and consults the compatibility check before
deciding whether to load the plugin. After scanning all plugins, KOReader
presents a UI listing plugins that were flagged as incompatible so the user
can choose an override action.
