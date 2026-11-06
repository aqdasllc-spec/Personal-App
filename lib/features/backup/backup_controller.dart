import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../library/application/library_controller.dart';
import 'backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider), ref.watch(syncedStoreProvider), libraryDir: ref.watch(libraryDirectoryProvider)));

/// Where backup files are written before being handed to the share sheet. Overridden in tests.
final backupTempDirProvider = Provider<Future<Directory> Function()>((ref) => () async => Directory('${(await getTemporaryDirectory()).path}/backups'));

/// Hands the file to the OS share sheet (save to Files/Drive, send, ...). True unless the user dismissed it.
final backupSharerProvider = Provider<Future<bool> Function(File)>((ref) => (file) async {
      final r = await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Folio backup', text: 'Folio backup'));
      return r.status != ShareResultStatus.dismissed;
    });

/// Lets the user choose a backup file. Overridden in tests.
final backupPickerProvider = Provider<Future<String?> Function()>((ref) => () async {
      final files = await FilePicker.pickFiles(type: FileType.any);
      return files.isEmpty ? null : files.first.path;
    });

const lastBackupKey = 'last_backup_at';

/// When the user last saved a backup (null = never).
final lastBackupProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final v = await ref.watch(syncedStoreProvider).state(lastBackupKey);
  final ms = int.tryParse(v ?? '');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
});

/// How much there is to lose: used to decide whether to nudge about backups.
final dataSummaryProvider = FutureProvider.autoDispose<({int tasks, int events, int books})>((ref) async {
  final s = await ref.watch(backupServiceProvider).summary();
  return s;
});
