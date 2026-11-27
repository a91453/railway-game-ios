# tools/translations

The languages beside English and Traditional Chinese (decision 1034). The game's
sentences are written at the call sites as `language.text(english, chinese)`;
another language is a table from each English sentence's key (the literal with
`{0}`, `{1}`, ... for its interpolations) to the language's sentence,
`Sources/GamePresentation/Translations/<Language>.swift`.

```sh
python3 -I tools/translations/extract.py --coverage ja          # how many sentences have Japanese
python3 -I tools/translations/batches.py ja OUT_DIR             # the missing ones, in batches for a translator
python3 -I tools/translations/merge.py ja OUT_DIR/ids.json A.txt B.txt   # add the translator's answers
```

`PROMPT-ja.md` is the translator's rules and glossary (Japanese railway terms,
place names, what stays untranslated), copied into every batch folder.
A new language: a `DisplayLanguage` case, a `TranslationTable` static, a line in
`table.py`'s `LANGUAGES`, and its own `PROMPT-<code>.md`.
