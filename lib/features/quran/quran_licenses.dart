import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Adds the Quran corner's fonts and texts to the app's licence page (Settings -> About -> Licences).
void registerQuranLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in const [
      ('Amiri Quran font', 'assets/fonts/OFL-amiriquran.txt'),
      ('Noto Nastaliq Urdu font', 'assets/fonts/OFL-notonastaliqurdu.txt'),
      ('Scheherazade New font', 'assets/fonts/OFL-scheherazadenew.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([pkg], await rootBundle.loadString(file));
    }
    yield const LicenseEntryWithLineBreaks(['Quran and hadith texts'], '''
Arabic Quran text (Uthmani script and Indo-Pak "Nastaleeq" script, Hafs): King Fahd Glorious Quran Printing Complex,
Madinah (qurancomplex.gov.sa); the Indo-Pak text as converted to Unicode by github.com/fawazahmed0/quran-api.
English translation: Saheeh International. Urdu translations: Fateh Muhammad Jalandhry, Muhammad Taqi Usmani, Muhammad
Junagarhi, Mahmood-ul-Hassan, Abul A'la Maududi (also in Roman Urdu), Ahmed Ali; as published by tanzil.net and others.
Hadith: Sahih al-Bukhari in Arabic, English (Muhammad Muhsin Khan) and Urdu.
Collected from the open datasets github.com/fawazahmed0/quran-api and github.com/fawazahmed0/hadith-api; the texts are
used verbatim, without changes. Recitation audio is streamed from cdn.islamic.network (Islamic Network).''');
    yield const LicenseEntryWithLineBreaks(['Tafsir'], '''
Tafsir texts (Ibn Kathir in Urdu and English, Bayan-ul-Quran by Dr. Israr Ahmad, Ma'ariful Qur'an by Mufti Muhammad Shafi)
are fetched from the open Tafsir API (github.com/spa5k/tafsir_api), which takes them from quran.com and the Quranic
Universal Library (qul.tarteel.ai). Shown verbatim.''');
    yield const LicenseEntryWithLineBreaks(['Morning and evening adhkar'], '''
From Hisn al-Muslim (Sa'id ibn Ali ibn Wahf al-Qahtani), as structured by the Morning and Evening Adhkar DB
(github.com/Seen-Arabic/Morning-And-Evening-Adhkar-DB).

MIT License

Copyright (c) 2024 Seen Arabic

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''');
  });
}
