# Kazakh support

Makes dictionary lookup work on inflected Kazakh words.

Kazakh is agglutinative. `мектептерімізде` is `мектеп` ("school") plus plural,
first-person-plural possessive and locative. Dictionaries are keyed on the
lemma, so tapping that word in a book finds nothing, and fuzzy search does not
rescue it: it measures *spelling* distance, not morphology.

The plugin hooks the same `LanguageSupport` WordLookup mechanism the Japanese
plugin uses for deinflection, and supplies extra dictionary-form candidates:

```
мектептерімізде  →  мектептеріміз, мектептері, мектептер, мектеп
кітабы           →  кітаб, кітап          (undoes б→п devoicing)
орны             →  орын                  (restores the elided vowel)
```

It offers every morphologically legal analysis rather than picking one stem,
and lets the dictionary decide which exist. A useful consequence: **no lexicon
is shipped or loaded.**

## Ranking

KOReader queries the tapped word first, then the plugin's candidates in the
order returned, concatenating results in that order — so an exact hit on the
tapped word always leads.

Intermediate rungs are usually not words, and KOReader resolves candidates with
fuzzy search on, so each would return near-spelling matches that sort above the
real article. The plugin therefore resolves its own candidates first with exact
search and passes on only those that exist, in ladder order, so the shallowest
analysis comes first. If that check cannot run, the unfiltered list is
returned.

The one source of noise it cannot remove is the tapped word's **own** fuzzy
matches, since KOReader queries it before the plugin is consulted. Unchecking
**Search → Settings → Dictionary settings → Enable fuzzy search** removes them.
With a book open that is a per-book setting, so it need not affect anything else
you read; long-press the item to change the default for new books.

## Requirements

At least one Kazakh StarDict dictionary in `koreader/data/dict/`. The book's
language must be detected as `kk`/`kaz`, or set it via
*Book information → Language*.

## Settings

*Menu → Search → Language support → Kazakh → Maximum candidates* (default 8).

## Implementation

| file | |
|---|---|
| `main.lua` | registers the plugin, implements `onWordLookup` |
| `stemmer.lua` | the ladder walk — suffix layers, vowel harmony, sound-change repair |
| `rules.lua` | **generated** suffix inventory; do not edit by hand |

Everything indexes by character, never by byte: Cyrillic is two bytes per
character in UTF-8, so byte offsets would put every length check and suffix
boundary in the wrong place.

The algorithm is a Lua port of
[kazsearch-py](https://github.com/iDynbek/kazsearch-py), itself a port of the
Rust core of [pg-kazsearch](https://github.com/darkhanakh/pg-kazsearch).
`rules.lua` is generated there by `tools/gen_lua_rules.py`, so the suffix
inventory cannot drift, and `tools/parity_lua.py` diffs the hand-ported walk
against the reference: 20,006 of 20,020 golden words identical, the remaining
14 single characters that this port drops by policy.

## Licence

Derived from pg-kazsearch by darkhanakh, licensed **LGPL-3.0-or-later**, and
distributed here under KOReader's **AGPL-3.0-or-later** — permitted by
LGPL-3.0 §2 and AGPL-3.0 §13.
