#!/usr/bin/env python3
"""Builds assets/quran/adhkar.json: the morning and evening adhkar.

Source: github.com/Seen-Arabic/Morning-And-Evening-Adhkar-DB (MIT licence), from Hisn al-Muslim (Sa'id al-Qahtani),
Arabic with English translation and transliteration, the number of times, its virtue and its hadith reference.
Nothing is typed by hand. For the adhkar that are ayahs of the Quran, only their reference is kept: the app shows
those ayahs from its own (checked) Quran text and translations.

Checks: 34 entries in both languages in the same order with the same Arabic; the Quranic entries are the expected
ayahs (checked by their English); each kind is morning (1), evening (2) or both (0).

Run:  python3 tool/quran/build_adhkar.py
"""
import json, os, sys, urllib.request

BASE = 'https://raw.githubusercontent.com/Seen-Arabic/Morning-And-Evening-Adhkar-DB/main/result'
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'quran', 'adhkar.json')

# order -> (surah, first ayah, last ayah, words the English must start with)
QURAN = {
    2: (2, 255, 255, 'Allah! There is none worthy of worship but He'),
    3: (2, 285, 286, '(285) The Messenger has believed'),
    4: (112, 1, 4, '(1) Say, He is Allah'),
    5: (113, 1, 5, '(1) Say, I seek refuge in the Lord of daybreak'),
    6: (114, 1, 6, '(1) Say, I seek refuge in the Lord of mankind'),
}


def get(name):
    with urllib.request.urlopen(f'{BASE}/{name}.json', timeout=60) as r:
        return json.load(r)


def main():
    ar, en = get('ar'), get('en')
    if len(ar) != 34 or len(en) != 34:
        sys.exit(f'expected 34 adhkar, got {len(ar)} / {len(en)}')
    out = []
    for a, e in zip(ar, en):
        if a['order'] != e['order'] or a['content'] != e['content']:
            sys.exit(f'Arabic and English differ at {a["order"]}')
        if a['type'] not in (0, 1, 2) or not isinstance(a['count'], int) or a['count'] < 1:
            sys.exit(f'bad kind or count at {a["order"]}')
        item = {
            'n': a['order'],
            'kind': a['type'],
            'count': a['count'],
            'source': a['source'].strip(),
            'virtue': (a.get('fadl') or '').strip(),
        }
        q = QURAN.get(a['order'])
        if q:
            if not e['translation'].startswith(q[3]):
                sys.exit(f'entry {a["order"]} is not the expected ayahs: {e["translation"][:60]}')
            item['quran'] = [q[0], q[1], q[2]]
            # what the book has said before the ayahs (the seeking of refuge): the words before the opening ornate
            # parenthesis, taken from the dataset itself
            cut = a['content'].find('\ufd3f')
            item['before'] = a['content'][:cut].strip() if cut > 0 else ''
        else:
            item['arabic'] = a['content'].strip()
            item['english'] = e['translation'].strip()
            item['translit'] = (e.get('transliteration') or '').strip()
        out.append(item)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(f'wrote {len(out)} adhkar ({sum(1 for x in out if "quran" in x)} from the Quran) to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
