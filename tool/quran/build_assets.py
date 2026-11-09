#!/usr/bin/env python3
"""Builds Folio's Quran and hadith data files (assets/quran/*.json.gz) from published open datasets.

Nothing here is typed by hand: every word comes from the sources below and is checked before it is written.

Sources (via the fawazahmed0/quran-api and fawazahmed0/hadith-api repositories on GitHub, branch "1"):
  Arabic   ara-quranuthmanihaf   Uthmani Hafs text, King Fahd Glorious Quran Printing Complex (qurancomplex.gov.sa)
  English  eng-ummmuhammad       Saheeh International (Umm Muhammad), via tanzil.net
  Urdu     urd-fatehmuhammadja   Fateh Muhammad Jalandhry, via tanzil.net
  Info     info.json             surah names, juz and sajda positions
  Hadith   ara/eng/urd-bukhari   Sahih al-Bukhari in Arabic, English (Muhsin Khan) and Urdu

Checks: 114 surahs, 6236 ayahs in each language, the three languages aligned ayah by ayah, Al-Fatiha 1:1 and
Ayat al-Kursi (2:255) spot checks; for hadith, the same numbering in all three languages, and only hadith whose
English narrator is also named in the Urdu text (so a mis-numbered entry can never be shown), and where the
Prophet's words can be found in the Urdu (the card shows them from there, verbatim; the full text is one tap away).

Run:  python3 tool/quran/build_assets.py            (downloads into a temporary folder)
      python3 tool/quran/build_assets.py --from DIR  (uses files already downloaded into DIR, named as below)
"""
import argparse, gzip, json, os, re, sys, tempfile, urllib.request

Q = 'https://raw.githubusercontent.com/fawazahmed0/quran-api/1'
H = 'https://raw.githubusercontent.com/fawazahmed0/hadith-api/1'
FILES = {
    'q-ara-quranuthmanihaf.json': f'{Q}/editions/ara-quranuthmanihaf.json',
    'q-eng-ummmuhammad.json': f'{Q}/editions/eng-ummmuhammad.json',
    'q-urd-fatehmuhammadja.json': f'{Q}/editions/urd-fatehmuhammadja.json',
    'q-info.json': f'{Q}/info.json',
    'h-ara-bukhari.json': f'{H}/editions/ara-bukhari.json',
    'h-eng-bukhari.json': f'{H}/editions/eng-bukhari.json',
    'h-urd-bukhari.json': f'{H}/editions/urd-bukhari.json',
}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'quran')

# English narrator -> how the Urdu translation spells the same companion.
NARRATORS = {
    'Abu Huraira': ['ابوہریرہ', 'ابو ہریرہ'],
    "'Aisha": ['عائشہ'], '`Aisha': ['عائشہ'],
    'Anas': ['انس'],
    "Ibn 'Umar": ['ابن عمر', 'عبداللہ بن عمر'], 'Ibn `Umar': ['ابن عمر', 'عبداللہ بن عمر'],
    "`Abdullah bin `Umar": ['عبداللہ بن عمر', 'ابن عمر'],
    "Ibn 'Abbas": ['ابن عباس', 'عبداللہ بن عباس'], 'Ibn `Abbas': ['ابن عباس', 'عبداللہ بن عباس'],
    "`Abdullah bin `Amr": ['عبداللہ بن عمرو'],
    'Jabir': ['جابر'],
    'Abu Musa': ['ابوموسیٰ', 'ابو موسیٰ', 'ابوموسی'],
    "Abu Sa'id": ['ابو سعید', 'ابوسعید'], 'Abu Sa`id': ['ابو سعید', 'ابوسعید'],
    'Abu Dhar': ['ابوذر', 'ابو ذر'],
    'An-Nu`man bin Bashir': ['نعمان بن بشیر'],
    '`Abdullah': ['عبداللہ'],
}


SAW = 'صلی اللہ علیہ وسلم'
SUBJECTS = ['رسول اللہ ', 'نبی کریم ', 'نبی ', 'آپ ']


def saying_start(u):
    """Where the Prophet's saying begins in an Urdu hadith (his mention right before "said"), skipping the chain
    of narrators; None if it cannot be found. The card shows u[start:] verbatim after an ellipsis."""
    best = None
    for m in re.finditer(re.escape(SAW), u):
        if 'فرمایا' in u[m.end():m.end() + 16]:
            best = m.start()
    if best is None:
        return None
    s = None
    for subj in SUBJECTS:
        k = u.rfind(subj, max(0, best - 20), best)
        if k >= 0 and (s is None or k > s):
            s = k
    if s is None:
        return None
    if u.startswith('آپ ', s):  # "...from the Prophet, he said": start at the Prophet's name
        for subj in ['رسول اللہ ', 'نبی کریم ']:
            k = u.rfind(subj, max(0, s - 45), s)
            if k >= 0:
                s = k
                break
    return s if 0 < s and len(u) - s >= 30 else None


def load(src, name):
    with open(os.path.join(src, name), encoding='utf-8') as f:
        return json.load(f)


def build_quran(src):
    ar = load(src, 'q-ara-quranuthmanihaf.json')['quran']
    en = load(src, 'q-eng-ummmuhammad.json')['quran']
    ur = load(src, 'q-urd-fatehmuhammadja.json')['quran']
    info = load(src, 'q-info.json')
    assert len(ar) == len(en) == len(ur) == 6236, 'expected 6236 ayahs in each language'
    for a, e, u in zip(ar, en, ur):
        assert a['chapter'] == e['chapter'] == u['chapter'] and a['verse'] == e['verse'] == u['verse'], (a, e, u)
        assert a['text'].strip() and e['text'].strip() and u['text'].strip(), a
    chapters = info['chapters']
    assert len(chapters) == 114
    assert sum(len(c['verses']) for c in chapters) == 6236
    assert ar[0]['text'] == 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ'
    assert en[0]['text'] == 'In the name of Allah, the Entirely Merciful, the Especially Merciful'
    k = next(i for i, v in enumerate(ar) if v['chapter'] == 2 and v['verse'] == 255)
    assert en[k]['text'].startswith('Allah - there is no deity except Him, the Ever-Living, the Sustainer of [all] existence')
    assert ar[k]['text'] and ar[k]['chapter'] == 2 and ar[k]['verse'] == 255
    surahs = [[c['chapter'], c['name'], c['englishname'], c['arabicname'],
               'Meccan' if c['revelation'].lower().startswith('mec') else 'Medinan', len(c['verses'])] for c in chapters]
    juz = [[r['start']['chapter'], r['start']['verse']] for r in info['juzs']['references']]
    sajda = [[r['chapter'], r['verse']] for r in info['sajdas']['references']]
    assert len(juz) == 30 and len(sajda) == 15
    return {
        'sources': {
            'arabic': 'Uthmani Hafs text, King Fahd Glorious Quran Printing Complex',
            'english': 'Saheeh International',
            'urdu': 'Fateh Muhammad Jalandhry (tanzil.net)',
        },
        'surahs': surahs, 'juz': juz, 'sajda': sajda,
        'ar': [v['text'].strip() for v in ar],
        'en': [v['text'].strip() for v in en],
        'ur': [v['text'].strip() for v in ur],
    }


def build_hadith(src):
    d = {l: {h['hadithnumber']: h for h in load(src, f'h-{l}-bukhari.json')['hadiths']} for l in ['ara', 'eng', 'urd']}
    assert len(d['ara']) == len(d['eng']) == len(d['urd'])
    items = []
    for n in sorted(d['eng']):
        e = d['eng'][n]
        t = e['text'].strip()
        u = d['urd'].get(n, {}).get('text', '').strip()
        a = d['ara'].get(n, {}).get('text', '').strip()
        if not (t and u and a):
            continue
        m = re.match(r'Narrated ([^:]+):', t)
        if not m:
            continue
        who = m.group(1).strip()
        keys = [key for key in NARRATORS if who == key or who.startswith(key + ' ')]
        if not keys or not any(x in u for x in NARRATORS[keys[0]]):
            continue  # numbering could be off for this one: leave it out
        if not ('(ﷺ)' in t and 'said' in t):
            continue
        if len(t) > 380 or len(u) > 620 or len(a) > 650 or '...' in t or 'ee Hadith' in t:
            continue
        start = saying_start(u)
        if start is None:
            continue  # the card could only show the chain of narrators: leave it out
        t = re.sub(r'^(Narrated [^:]+:)(\S)', r'\1 \2', t)  # a space after "Narrated X:" (layout only)
        ref = e.get('reference') or {}
        items.append([n if float(n).is_integer() else float(n), ref.get('book', 0), ref.get('hadith', 0), a, t, u, start])
    assert len(items) > 900, len(items)
    return {'collection': 'Sahih al-Bukhari', 'sources': {'english': 'Muhammad Muhsin Khan', 'urdu': 'Urdu translation (hadith-api)'}, 'items': items}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='src')
    args = ap.parse_args()
    src = args.src
    if not src:
        src = tempfile.mkdtemp()
        for name, url in FILES.items():
            print('downloading', url, file=sys.stderr)
            urllib.request.urlretrieve(url, os.path.join(src, name))
    os.makedirs(OUT, exist_ok=True)
    for name, data in [('quran.json.gz', build_quran(src)), ('hadith.json.gz', build_hadith(src))]:
        raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        with gzip.GzipFile(os.path.join(OUT, name), 'wb', compresslevel=9, mtime=0) as f:
            f.write(raw)
        print(name, len(raw), 'bytes before compression', file=sys.stderr)


if __name__ == '__main__':
    main()
