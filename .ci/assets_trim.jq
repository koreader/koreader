include "assets_parse";

[
  $ARGS.positional[] | asset_parse
  # Ignore latest stable / nightly files.
  | select(.latest | not)
] #| debug(flatten | sort_by(.sort_version) | .[].file)
# Group by stable / nightly…
| [
  [.[] | select(.stable)],
  [.[] | select(.stable | not)]
] #| debug
# …and each list in turn by decreasing version.
| map(group_by(.sort_version) | reverse)
| {
  "stables"  : .[0],
  "nightlies": .[1],
} #| debug
# Determine newest discarded stable version.
| (.stables[$stable_keep_count][0].sort_version // [-1]) as $newest_discarded_stable_version
| [
    # Discard all stables after the last $stable_keep_count versions.
    .stables[$stable_keep_count:],
    # Discard all nightlies after the last $nightly_keep_count versions.
    .nightlies[$nightly_keep_count:],
    # Also discard all nightlies older than $newest_discarded_stable_version.
    [.nightlies[] | select(.[0].sort_version < $newest_discarded_stable_version)]
]
| flatten | .[].file

# vim: sw=2
