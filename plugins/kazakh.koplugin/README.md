# Kazakh support

Makes dictionary lookup work on inflected Kazakh words.

Kazakh is agglutinative. `мектептерімізде` is `мектеп` ("school") plus plural,
first-person-plural possessive and locative. Dictionaries are keyed on the
lemma, so tapping that word in a book finds nothing. StarDict's fuzzy search
does not rescue it either: fuzzy search measures *spelling* distance, and a
four-suffix word is nowhere near its root by that measure.

This plugin hooks the same `LanguageSupport` WordLookup mechanism the Japanese
plugin uses for deinflection, and supplies extra dictionary-form candidates:

```
мектептерімізде  →  мектептеріміз, мектептері, мектептер, мектеп
кітабы           →  кітаб, кітап          (undoes б→п devoicing)
орны             →  орын                  (restores the elided vowel)
```

## Why it offers several candidates instead of one stem

Because picking one is where stemmers fail, and they fail in *both* directions:

| word | a scorer picks | the real root |
|---|---|---|
| `маманда` | `мама` | `маман` — stripped too far |
| `жанышта` | `жанышта` | `жаныш` — not stripped at all |

In both cases the correct root is reachable; only the scoring rejects it. So
this plugin does not score. It returns every morphologically legal analysis and
lets the dictionary decide which ones exist — the same approach the Japanese
plugin takes with deinflection candidates.

A useful consequence: **no lexicon is shipped or loaded.** The dictionary is
the filter, so the plugin is a few small Lua files and no data.

## Ranking: getting the right entry first

Two things decide what lands at the top of the lookup popup.

**KOReader queries the tapped word first**, then the plugin's candidates in the
order the plugin returns them, and concatenates the results in that order. So
an exact hit on the tapped word is always first — that part is free.

**The plugin verifies its candidates before offering them.** Intermediate rungs
are usually not words: `мектептерімізде` yields `мектептері` and `мектептер`,
neither a dictionary entry. But KOReader looks candidates up with *fuzzy*
search, so each returns a handful of near-spelling matches, and that noise
sorts above the real article:

| | before | after |
|---|---|---|
| `мектептерімізде` | МЕКТЕПТЕС, МЕКТЕПТЕСТЕЙ, Мектепті, МЕКТЕПТЕС, МЕКЕТТЕР, МЕКТЕПТІК, МЕКТЕПТАНУ, Мектепті, **МЕКТЕП** *(9th)* | **МЕКТЕП** *(only)* |

So the plugin resolves its own candidates first with exact search and passes on
only the ones that exist. Surviving candidates keep ladder order, which means
the *shallowest* analysis comes first — for `маманда` that is `маман`, not the
over-stripped `мама`.

If the check cannot run, the unfiltered list is returned: this can only add
precision, never lose a result.

### Turn off fuzzy search

The one source of noise the plugin cannot remove is the **tapped word's own**
fuzzy matches — KOReader queries it before the plugin is consulted. Tapping
`маманда` returns МАМАНДАН, Аманда, ЖАМАНДА… ahead of `Маман`.

Fuzzy search exists to paper over inflection, which this plugin now handles
properly, so for Kazakh it only adds noise. Turn it off in
**☰ → Settings → Dictionary → Disable fuzzy search**:

```
маманда          →  Маман, Ана, МАМА          (was: 8 near-spellings first)
мектептерімізде  →  МЕКТЕП
```

Note this is a global setting; if you also read in languages without a
morphology plugin, fuzzy search is still useful there.

## Requirements

At least one Kazakh StarDict dictionary in `koreader/data/dict/`. The book's
language must be detected as `kk`/`kaz`, or set it via
*Book information → Language*.

## Settings

*Menu → Search → Language support → Kazakh → Maximum candidates* (default 8).
Deeper analyses are shorter and less likely to be the intended word; lowering
this narrows the sdcv call.

## Implementation

| file | |
|---|---|
| `main.lua` | registers the plugin, implements `onWordLookup` |
| `stemmer.lua` | the ladder walk — suffix layers, vowel harmony, sound-change repair |
| `rules.lua` | **generated** suffix inventory; do not edit by hand |

The algorithm is a Lua port of
[kazsearch-py](https://github.com/iDynbek/kazsearch-py), itself a port of the
Rust core of [pg-kazsearch](https://github.com/darkhanakh/pg-kazsearch).
`rules.lua` is generated from the Python source by `tools/gen_lua_rules.py`
there, so the suffix inventory cannot drift; `tools/parity_lua.py` checks the
hand-ported walk against the reference.

Latest run — 20,020 words, hand-picked edge cases plus real tokens from a
215k-article Kazakh dictionary corpus:

```
20,006/20,020 identical
14 differ only by the single-character policy
0 unexplained
```

The 14 are single characters, where the reference returns the character and
this port returns nothing: KOReader has already looked the tapped word up, so a
one-character candidate can only duplicate it.

Two things the port has to get right, and both are silent when wrong:

**Everything indexes by character, never by byte.** Cyrillic is two bytes per
character in UTF-8, so byte offsets put every length check and suffix boundary
in the wrong place. That includes the final sort, where `#s` would compare
bytes.

**Glides are transparent to vowel harmony.** `у`, `и` and `ю` carry no harmony
class, so a loanword like `туризм` has none either and must accept suffixes of
both classes. Without that it is unstemmable.

## Known limitation

Words whose only vowel is `ю` — `шлюз` — have zero syllables by the algorithm's
reckoning, so no suffix strip is ever legal and the ladder has a single rung.
This is inherited from the reference implementation.

## Licence

Derived from pg-kazsearch by darkhanakh, licensed **LGPL-3.0-or-later**, and
distributed here under KOReader's **AGPL-3.0-or-later** — permitted by
LGPL-3.0 §2 and AGPL-3.0 §13.
