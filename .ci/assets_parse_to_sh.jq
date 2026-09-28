include "assets_parse";

[$ARGS.positional[] | asset_parse]
| sort_by([.platform, .sort_version, .extension])
| .[]
| to_entries
| map("[" + (.key | @sh) + "]=" + (.value | tostring | @sh))
| join(" ")
