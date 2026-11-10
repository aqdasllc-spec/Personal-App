#!/usr/bin/env python3
"""Builds Folio's Quran and hadith data files (assets/quran/*.json.gz) from published open datasets.

Nothing here is typed by hand: every word comes from the sources below and is checked before it is written.

Sources (via the fawazahmed0/quran-api and fawazahmed0/hadith-api repositories on GitHub, branch "1"):
  Arabic   ara-quranuthmanihaf   Uthmani Hafs text, King Fahd Glorious Quran Printing Complex (qurancomplex.gov.sa)
  Indo-Pak ara-quranindopak      "Quran Nastaleeq" (Indo-Pak script) text of the same Complex, in Unicode
  Urdu+    urd-muhammadtaqiusm, urd-muhammadjunagar, urd-mahmoodulhassan, urd-abulaalamaududi, urd-ahmedali, urd-abulaalamaududi-la (Roman Urdu): further translations to choose from
  English  eng-ummmuhammad       Saheeh International (Umm Muhammad), via tanzil.net
  Urdu     urd-fatehmuhammadja   Fateh Muhammad Jalandhry, via tanzil.net
  Search   ara-quransimple       Tanzil "simple" text (everyday spelling), vowel marks removed: for searching only
  Info     info.json             surah names, juz, sajda and page positions
  Hadith   ara/eng/urd-bukhari   Sahih al-Bukhari in Arabic, English (Muhsin Khan) and Urdu

Checks: 114 surahs, 6236 ayahs in each language, the three languages aligned ayah by ayah, Al-Fatiha 1:1 and
Ayat al-Kursi (2:255) spot checks; for hadith, the same numbering in all three languages, and only hadith whose
English narrator is also named in the Urdu text (so a mis-numbered entry can never be shown), and where the
Prophet's words can be found in the Urdu (the card shows them from there, verbatim; the full text is one tap away).

Run:  python3 tool/quran/build_assets.py            (downloads into a temporary folder)
      python3 tool/quran/build_assets.py --from DIR  (uses files already downloaded into DIR, named as below)
"""
import argparse, difflib, gzip, json, os, re, sys, tempfile, unicodedata, urllib.request

Q = 'https://raw.githubusercontent.com/fawazahmed0/quran-api/1'
H = 'https://raw.githubusercontent.com/fawazahmed0/hadith-api/1'
FILES = {
    'q-ara-quranuthmanihaf.json': f'{Q}/editions/ara-quranuthmanihaf.json',
    'q-eng-ummmuhammad.json': f'{Q}/editions/eng-ummmuhammad.json',
    'q-urd-fatehmuhammadja.json': f'{Q}/editions/urd-fatehmuhammadja.json',
    'q-ara-quransimple.json': f'{Q}/editions/ara-quransimple.json',
    'q-ara-quranindopak.json': f'{Q}/editions/ara-quranindopak.json',
    'q-info.json': f'{Q}/info.json',
    'h-ara-bukhari.json': f'{H}/editions/ara-bukhari.json',
    'h-eng-bukhari.json': f'{H}/editions/eng-bukhari.json',
    'h-urd-bukhari.json': f'{H}/editions/urd-bukhari.json',
}
# More Urdu translations, offered as choices (Jalandhry stays the default, inside quran.json.gz).
# edition, file id, name shown, right-to-left?
URDU = [
    ('urd-muhammadtaqiusm', 'taqiusmani', 'Mufti Muhammad Taqi Usmani', True),
    ('urd-muhammadjunagar', 'junagarhi', 'Muhammad Junagarhi', True),
    ('urd-mahmoodulhassan', 'mahmoodulhassan', 'Shaykh-ul-Hind Mahmood-ul-Hassan', True),
    ('urd-abulaalamaududi', 'maududi', "Abul A'la Maududi", True),
    # urd-muhammadtahirul (Tahir-ul-Qadri) is left out: 217 ayahs are empty in the source (e.g. all of Al-A'raf)
    ('urd-ahmedali', 'ahmedali', 'Ahmed Ali', True),
    ('urd-abulaalamaududi-la', 'maududiroman', "Abul A'la Maududi (Roman Urdu)", False),
]
for _e, _id, _n, _r in URDU:
    FILES[f'q-{_e}.json'] = f'{Q}/editions/{_e}.json'

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
    # the Indo-Pak (South Asian) script: KFGQPC "Quran Nastaleeq" text in Unicode (same ayahs, Indo-Pak spelling and
    # marks); the right-to-left mark some ayahs end with is dropped
    ip = load(src, 'q-ara-quranindopak.json')['quran']
    assert len(ip) == 6236 and all(x['chapter'] == y['chapter'] and x['verse'] == y['verse'] for x, y in zip(ip, ar))
    ip = [v['text'].replace('\u200f', '').strip() for v in ip]
    assert all(ip)
    assert ip[0].startswith('بِسۡمِ') and ip[0].endswith('الرَّحِيۡمِ'), ip[0]
    # the same ayahs: the consonants of each ayah (long-vowel letters, marks and spaces left out, letter forms folded)
    # must match the Uthmani text's; they do for every ayah (6235 exactly, the lowest 97.8%, a spelling difference)
    fold = {'\u0629': '\u0647', '\u06C1': '\u0647', '\u06BE': '\u0647', '\u06CC': '\u064A', '\u0649': '\u064A',
            '\u06D2': '\u064A', '\u06A9': '\u0643', '\u0624': '\u0648', '\u0626': '\u064A'}
    keep = re.compile('[\u0628-\u063A\u0641-\u0648\u064A\u0629\u06C1\u06BE\u06CC\u06D2\u06A9\u0649\u0624\u0626]')
    def skeleton(t):
        return ''.join(c for c in (fold.get(c, c) for c in t if keep.match(c)) if c not in '\u0648\u064A')
    worst = min(difflib.SequenceMatcher(None, skeleton(a['text']), skeleton(b)).ratio() for a, b in zip(ar, ip))
    assert worst >= 0.95, f'an Indo-Pak ayah differs from the Uthmani one (match {worst:.2f})'
    surahs = [[c['chapter'], c['name'], c['englishname'], c['arabicname'],
               'Meccan' if c['revelation'].lower().startswith('mec') else 'Medinan', len(c['verses'])] for c in chapters]
    # search only: the same ayahs in everyday ("imlaei") spelling, vowel marks removed (never shown)
    simple = load(src, 'q-ara-quransimple.json')['quran']
    assert len(simple) == 6236 and all(x['chapter'] == y['chapter'] and x['verse'] == y['verse'] for x, y in zip(simple, ar))
    marks = re.compile('[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]')
    search = [re.sub(r'\s+', ' ', marks.sub('', v['text'])).strip() for v in simple]
    assert all(search)
    pages = [v['page'] for c in chapters for v in c['verses']]  # Madinah mushaf page of each ayah
    assert len(pages) == 6236 and pages[0] == 1 and pages[-1] == 604 and len(set(pages)) == 604
    assert all(b >= a for a, b in zip(pages, pages[1:]))
    juz = [[r['start']['chapter'], r['start']['verse']] for r in info['juzs']['references']]
    sajda = [[r['chapter'], r['verse']] for r in info['sajdas']['references']]
    assert len(juz) == 30 and len(sajda) == 15
    return {
        'sources': {
            'arabic': 'Uthmani Hafs text, King Fahd Glorious Quran Printing Complex',
            'english': 'Saheeh International',
            'urdu': 'Fateh Muhammad Jalandhry (tanzil.net)',
        },
        'surahs': surahs, 'juz': juz, 'sajda': sajda, 'page': pages, 'ars': search,
        'ar': [v['text'].strip() for v in ar],
        'en': [v['text'].strip() for v in en],
        'ur': [v['text'].strip() for v in ur],
        'ip': ip,
    }


def build_urdu(src, edition, ar):
    u = load(src, f'q-{edition}.json')['quran']
    assert len(u) == 6236 and all(x['chapter'] == y['chapter'] and x['verse'] == y['verse'] for x, y in zip(u, ar)), edition
    texts = [tidy_urdu(v['text']) for v in u]
    assert all(texts), edition
    return texts


KEEP_FORMS = {'\uFD3E', '\uFD3F', '\uFDFA', '\uFDF2'}  # the ornate brackets, the salutation sign and the name of Allah


def tidy_urdu(t):
    """Display clean-up only, never a change of wording: Arabic "presentation forms" (old encodings of joined letter
    shapes, e.g. U+FEFB for lam-alef, that Urdu fonts may not draw) become the ordinary letters they stand for (their
    standard Unicode equivalent), and footnote numbers like [12] (the notes are not part of the data) are removed."""
    t = ''.join(unicodedata.normalize('NFKC', c) if ('\uFB50' <= c <= '\uFDFF' or '\uFE70' <= c <= '\uFEFF') and c not in KEEP_FORMS else c
                for c in t.replace('\u200f', ''))
    t = re.sub(r'\s*\[[\u06F0-\u06F9\u0660-\u06690-9]+\]', '', t)
    return re.sub(r'\s+', ' ', t).strip()


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
    ar = load(src, 'q-ara-quranuthmanihaf.json')['quran']
    extra = [(f'ur_{fid}.json.gz', {'name': n, 'rtl': rtl, 'ur': build_urdu(src, e, ar)}) for e, fid, n, rtl in URDU]
    for name, data in [('quran.json.gz', build_quran(src)), ('hadith.json.gz', build_hadith(src)), *extra]:
        raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        with gzip.GzipFile(os.path.join(OUT, name), 'wb', compresslevel=9, mtime=0) as f:
            f.write(raw)
        print(name, len(raw), 'bytes before compression', file=sys.stderr)


if __name__ == '__main__':
    main()
