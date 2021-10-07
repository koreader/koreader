## Japanese Support Plugin for KOReader ##

This plugin is heavily based on Yomichan's design, and makes use of Yomichan's
deinflection data, but was written specifically for KOReader. There are two
major features implemented by this plugin:

 1. Verb deinflection (aka deconjugation) support, based on Yomichan's very
    elegant rule-matching suffix replacement system using Yomichan's data.

 2. Text segmentation support without needing MeCab or any other binary helper,
    by re-using the users' installed dictionaries to exhaustively try every
    length of text and select the longest match which is present in the
    dictionary. This is similar to how Yomichan does MeCab-less segmentation.

    On paper this plugin should also be work with Chinese text if the user has
    Chinese dictionaries installed, though that is not its primary intended
    use-case.

The backbone of this plugin is the included `yomichan-deinflect.json`. This
file is copied verbatim from [Yomichan's `ext/data/deinflect.json`][yomichan-deinflect.json]
and can be updated when necessary by simply getting a newer copy.

Note that Yomichan and KOReader use the same license (GPL-3.0-or-later) so any
theoretical licensing problems are a non-issue.

[yomichan-deinflect.json]: https://github.com/FooSoft/yomichan/blob/21.9.30.0/ext/data/deinflect.json
