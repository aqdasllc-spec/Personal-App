import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A book's metadata as stored in the cloud.
class CloudBook {
  const CloudBook({required this.id, required this.title, required this.author, required this.pageCount, required this.sizeBytes, required this.sha256});
  final String id, title, author, sha256;
  final int pageCount, sizeBytes;
}

class CloudException implements Exception {
  CloudException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The user's private cloud shelf: one PDF + one metadata row per synced book.
abstract interface class CloudBooks {
  Future<void> upload(CloudBook book, File file);

  /// Deletes the cloud copy. Succeeds if it is already gone.
  Future<void> remove(String bookId);
  Future<List<CloudBook>> list();
  Future<void> download(String bookId, File destination);
}

/// Supabase Storage (private bucket `books`, folder = user id) + table `cloud_books`.
/// Row-level security keeps every user inside their own folder/rows (supabase/migrations).
class SupabaseCloudBooks implements CloudBooks {
  SupabaseCloudBooks(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser?.id ?? (throw CloudException('Sign in to use cloud sync.'));
  String _path(String id) => '$_uid/$id.pdf';

  Never _fail(Object e) {
    if (e is CloudException) throw e;
    if (e is StorageException) {
      final m = e.message.toLowerCase();
      if (e.statusCode == '413' || m.contains('too large') || m.contains('exceeded') || m.contains('maximum allowed size')) {
        throw CloudException('This PDF is larger than your cloud plan allows (the free plan accepts files up to 50 MB).');
      }
      if (m.contains('bucket not found')) throw CloudException('The cloud storage is not set up yet. Run the latest setup SQL in Supabase.');
      throw CloudException(e.message);
    }
    if (e is PostgrestException) {
      if (e.code == 'PGRST205' || e.code == '42P01') throw CloudException('The cloud tables are not set up yet. Run the latest setup SQL in Supabase.');
      throw CloudException(e.message);
    }
    throw CloudException('Can\'t reach the cloud. Check your connection and try again.');
  }

  @override
  Future<void> upload(CloudBook b, File file) async {
    try {
      await _client.storage.from('books').upload(_path(b.id), file, fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'));
      await _client.from('cloud_books').upsert({
        'owner_id': _uid,
        'id': b.id,
        'title': b.title,
        'author': b.author,
        'page_count': b.pageCount,
        'size_bytes': b.sizeBytes,
        'sha256': b.sha256,
      });
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> remove(String bookId) async {
    try {
      await _client.storage.from('books').remove([_path(bookId)]);
      await _client.from('cloud_books').delete().eq('id', bookId);
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<List<CloudBook>> list() async {
    try {
      final rows = await _client.from('cloud_books').select().order('created_at');
      return [
        for (final r in rows)
          CloudBook(
            id: r['id'] as String,
            title: (r['title'] as String?) ?? '',
            author: (r['author'] as String?) ?? '',
            pageCount: (r['page_count'] as num?)?.toInt() ?? 0,
            sizeBytes: (r['size_bytes'] as num?)?.toInt() ?? 0,
            sha256: (r['sha256'] as String?) ?? '',
          )
      ];
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> download(String bookId, File destination) async {
    try {
      final bytes = await _client.storage.from('books').download(_path(bookId));
      await destination.writeAsBytes(bytes, flush: true);
    } catch (e) {
      _fail(e);
    }
  }
}
