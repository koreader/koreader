include "assets_parse";

[$ARGS.positional[] | asset_parse]
# Sort: OTA files last.
| sort_by([.ota, .sort_version, .platform, .extension])
# Filter-out:
# - nightly: no ZIP for kindle and the like
# - stable: no OTA, and ZIP only for kindle and the like
| .[] | select(
  if $channel == "nightly" then
    .extension != "zip"
  else
    .ota != true and ((.platform | test("^linux")) or (.extension != "tar.xz" and .extension != "targz"))
  end
)
# And label.
| .file + "#" + ([
  .platform_name,
  if .commit_number then .base_version + "-" + .commit_number else .base_version end,
  "(" + .extension + ")"
] | join(" "))

# vim: sw=2
