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
Arabic Quran text (Uthmani script, Hafs): King Fahd Glorious Quran Printing Complex, Madinah (qurancomplex.gov.sa).
English translation: Saheeh International. Urdu translation: Fateh Muhammad Jalandhry. Both as published by tanzil.net.
Hadith: Sahih al-Bukhari in Arabic, English (Muhammad Muhsin Khan) and Urdu.
Collected from the open datasets github.com/fawazahmed0/quran-api and github.com/fawazahmed0/hadith-api; the texts are
used verbatim, without changes. Recitation audio is streamed from cdn.islamic.network (Islamic Network).''');
  });
}
