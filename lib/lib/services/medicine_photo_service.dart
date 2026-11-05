import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Photos stay behind authenticated Storage rules; no public token URL is stored.
class MedicinePhotoService {
  static const maxPhotos = 4;
  static const maxBytes = 5 * 1024 * 1024;
  static List<String> paths(Map<String, dynamic> data) =>
      (data['photoPaths'] is List ? data['photoPaths'] as List : const [])
          .whereType<String>().take(maxPhotos).toList();

  static Future<List<String>> upload(String uid, String medicineId, List<File> files,
      {void Function(double)? onProgress}) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Sign in again to save medicine photos.');
    if (files.isEmpty || files.length > maxPhotos) throw StateError('Choose 1–4 medicine photos.');
    final paths = <String>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final bytes = await files[i].readAsBytes();
        if (bytes.isEmpty || bytes.length > maxBytes) throw StateError('Each photo must be smaller than 5 MB.');
        String? mime;
        String? ext;
        if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
          mime = 'image/jpeg'; ext = 'jpg';
        } else if (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71) {
          mime = 'image/png'; ext = 'png';
        } else if (bytes.length >= 12 && String.fromCharCodes(bytes.sublist(0,4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8,12)) == 'WEBP') {
          mime = 'image/webp'; ext = 'webp';
        }
        if (mime == null) throw StateError('Choose a JPEG, PNG or WebP photo.');
        final token = FirebaseFirestore.instance.collection('medicines').doc().id;
        final path = 'medicine_photos/$uid/$medicineId/$token.$ext';
        await _uploadOne(path, bytes, mime, (value) {
          onProgress?.call((i + value) / files.length);
        });
        // Only tracked as "ours to roll back" once the upload genuinely
        // finished — adding it before that meant a failed/retried attempt
        // could ask to delete an object that was never actually written,
        // which Storage (correctly) reports as object-not-found.
        paths.add(path);
      }
      return paths;
    } catch (_) {
      await remove(paths);
      rethrow;
    }
  }

  // A resumable upload session can be invalidated by a brief connection
  // drop (very common on a weak/slow connection) partway through; the
  // client then gets a confusing error — often object-not-found — trying
  // to finalize a session the server already discarded. That's transient,
  // so a couple of fresh retries (a brand-new putData call, not resuming
  // the broken session) clears it almost every time without the user
  // having to notice or re-pick the photo.
  static Future<void> _uploadOne(String path, Uint8List bytes, String mime, void Function(double) onProgress) async {
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final task = FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: mime));
      final sub = task.snapshotEvents.listen((snap) {
        onProgress(snap.totalBytes == 0 ? 0 : snap.bytesTransferred / snap.totalBytes);
      });
      try {
        await task.timeout(const Duration(seconds: 60), onTimeout: () async {
          await task.cancel(); throw StateError('Photo upload timed out. Try again.');
        });
        return;
      } on FirebaseException catch (e) {
        final transient = e.code == 'object-not-found' || e.code == 'unknown' ||
            e.code == 'retry-limit-exceeded' || e.code == 'cancelled';
        if (!transient || attempt == attempts) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      } finally { await sub.cancel(); }
    }
  }

  static Future<void> remove(List<String> paths) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    for (final path in paths) {
      if (uid == null || !path.startsWith('medicine_photos/$uid/')) continue;
      try { await FirebaseStorage.instance.ref(path).delete().timeout(const Duration(seconds: 10)); }
      catch (_) { /* Best effort only: a storage failure must not undo a saved record. */ }
    }
  }
}