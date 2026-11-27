"""Reads and writes a language's table, Sources/GamePresentation/Translations/<Name>.swift
(decision 1034): one `key<TAB>sentence` line per sentence inside a raw string,
with a backslash, a tab and a line break written as \\\\, \\t and \\n."""

# Each language the tables hold: its code, the file's name, the static
# property TranslationTable reads.
LANGUAGES = {"ja": ("Japanese", "japaneseSource")}

HEAD = r'''// The game's {name} (decision 1034), written by tools/translations/merge.py
// from the translators' answers; add to it with that tool rather than by hand.
// One line per sentence: the English key (`DisplayTextTemplate.key`), a tab,
// the {name}; `\\`, `\t` and `\n` stand for a backslash, a tab and a line
// break.

extension TranslationTable {{
    static let {property} = #"""
'''
TAIL = '''"""#
}
'''


def escape(text):
    return text.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def unescape(text):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append({"\\": "\\", "t": "\t", "n": "\n"}.get(n, "\\" + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def read(path):
    rows = {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    body = text.split('#"""\n', 1)[1].rsplit('"""#', 1)[0]
    for line in body.split("\n"):
        if not line:
            continue
        key, _, value = line.partition("\t")
        rows[unescape(key)] = unescape(value)
    return rows


def path_of(root, language):
    import os
    return os.path.join(root, "Sources/GamePresentation/Translations", LANGUAGES[language][0] + ".swift")


def write(path, rows, language="ja"):
    name, prop = LANGUAGES[language]
    with open(path, "w", encoding="utf-8") as f:
        f.write(HEAD.format(name=name, property=prop))
        for key in sorted(rows):
            f.write(escape(key) + "\t" + escape(rows[key]) + "\n")
        f.write(TAIL)
