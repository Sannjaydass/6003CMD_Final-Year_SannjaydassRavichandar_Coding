import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Turns a raw Gemini error ("HTTP 402", "HTTP 429", an exception string,
/// …) into something safe and useful to show a user — never the bare
/// status code, which means nothing to someone trying to log a BP reading.
///
/// "HTTP 402 Payment Required" specifically means the API key's Google
/// Cloud project has hit a billing/quota wall — the key itself is fine,
/// Google is refusing to serve more requests on it until billing is sorted
/// (Google AI Studio → that project → Billing), or a fresh key is swapped
/// in at [GeminiService.apiKey]. It is NOT something this app can retry its
/// way out of.
String friendlyGeminiError(Object error) {
  final s = error.toString();
  if (s.contains('402')) {
    return 'AI photo reading is temporarily unavailable (the AI service needs billing set up). '
        'You can still enter this reading manually below.';
  }
  if (s.contains('429')) {
    return 'AI photo reading is busy right now — please wait a moment and try again.';
  }
  if (s.contains('403') || s.contains('401')) {
    return 'AI photo reading is temporarily unavailable. You can still enter this reading manually below.';
  }
  return 'Could not read this photo automatically. You can still enter the reading manually below.';
}

class GeminiService {
  // Single source of truth for the Gemini API key/endpoint — every AI
  // feature in the app (medicine scanning, vitals photo reading, the
  // health-analysis chat, safe-disposal lookup) reads it from here instead
  // of each keeping its own copy, so rotating the key is a one-line change
  // instead of hunting through 6 files.
  //
  // SECURITY: this key ships inside the compiled app, which means anyone
  // who decompiles the APK can read and reuse it — that's the most likely
  // reason it started returning "402 Payment Required" (its free quota
  // got burned through by more than just this app's own users, or its
  // project's billing got capped). The durable fix is to move these Gemini
  // calls behind a Cloud Function (functions/ already exists in this
  // project) so the real key never ships to a device and the app calls
  // your own authenticated endpoint instead. Until that's done, get AI
  // features working again by generating a fresh key at
  // https://aistudio.google.com/apikey and pasting it below.
  static const String apiKey = 'AIzaSyDoC8N6L66jdHvXA6KlIO4ulsSSS5Oyves';
  static const String baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  /// Backwards-compatible single-image analysis.
  Future<Map<String, dynamic>> analyzeMedicineImage(File imageFile) =>
      analyzeMedicineImages([imageFile]);

  /// Analyze up to 2 medicine photos together.
  /// Photo 1 = clinical / pharmacy label, Photo 2 = medicine packaging.
  /// If the expiry date is not printed anywhere, Gemini estimates one from the
  /// manufacturing date + typical shelf life for that medicine type and marks
  /// expiryDateSource as "ai".
  Future<Map<String, dynamic>> analyzeMedicineImages(List<File> imageFiles) async {
    try {
      if (imageFiles.isEmpty) {
        return {'success': false, 'error': 'No image provided'};
      }

      final promptText = imageFiles.length > 1
          ? '''You are given ${imageFiles.length} photos of the SAME medicine:
- Photo 1 is the CLINICAL / PHARMACY LABEL (patient sticker, dispensing label, prescription label).
- Photo 2 is the MEDICINE PACKAGING (box, blister strip, bottle).

Cross-reference BOTH photos to extract the most accurate, complete information. Prefer the clinical label for patient-specific instructions and the packaging for manufacturer, batch, and expiry data. Return the following information strictly in JSON format:
$_jsonSchema

Rules for expiryDate:
1. If an expiry date is clearly printed on either photo, use it and set "expiryDateSource" to "label".
2. If NO expiry date is visible but a manufacturing date is, estimate the expiry as manufacturing date + the typical shelf life for this medicine type (usually 24-36 months; use 24 months if unsure) and set "expiryDateSource" to "ai".
3. If neither date is visible, estimate a conservative expiry of today + 12 months, set "expiryDateSource" to "ai".
Always return a valid DD/MM/YYYY expiryDate — never "Not visible" for expiryDate. Today's date is $_today.

For all OTHER fields, if information is not visible in either photo, use "Not visible". Be accurate and only extract what is clearly visible.'''
          : '''Analyze this medicine image and extract the following information in JSON format:
$_jsonSchema

Rules for expiryDate:
1. If an expiry date is clearly printed, use it and set "expiryDateSource" to "label".
2. If NO expiry date is visible but a manufacturing date is, estimate the expiry as manufacturing date + the typical shelf life for this medicine type (usually 24-36 months; use 24 months if unsure) and set "expiryDateSource" to "ai".
3. If neither date is visible, estimate a conservative expiry of today + 12 months, set "expiryDateSource" to "ai".
Always return a valid DD/MM/YYYY expiryDate — never "Not visible" for expiryDate. Today's date is $_today.

For all OTHER fields, if any information is not visible or unclear in the image, use "Not visible". Be accurate and only extract information that is clearly visible.''';

      final parts = <Map<String, dynamic>>[
        {'text': promptText},
      ];
      for (final f in imageFiles) {
        final bytes = await f.readAsBytes();
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(bytes),
          }
        });
      }

      final response = await http.post(
        Uri.parse('$baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {'parts': parts}
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'];

        String cleanedText = text.trim();
        if (cleanedText.startsWith('```json')) {
          cleanedText = cleanedText.substring(7);
        }
        if (cleanedText.startsWith('```')) {
          cleanedText = cleanedText.substring(3);
        }
        if (cleanedText.endsWith('```')) {
          cleanedText = cleanedText.substring(0, cleanedText.length - 3);
        }
        cleanedText = cleanedText.trim();

        final medicineData = jsonDecode(cleanedText);

        return {
          'success': true,
          'data': medicineData,
          'rawResponse': text,
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to analyze image: ${response.statusCode}',
          'message': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Error analyzing image: ${e.toString()}',
      };
    }
  }

  static String get _today {
    final n = DateTime.now();
    return '${n.day}/${n.month}/${n.year}';
  }

  static const String _jsonSchema = '''{
  "medicineName": "full medicine name",
  "genericName": "generic/scientific name if visible",
  "dosage": "dosage strength (e.g., 500mg, 10ml)",
  "expiryDate": "expiry date in DD/MM/YYYY format",
  "expiryDateSource": "label OR ai",
  "manufacturingDate": "manufacturing date in DD/MM/YYYY format if visible",
  "batchNumber": "batch/lot number if visible",
  "manufacturer": "manufacturer name",
  "usage": "what this medicine is used for",
  "dosageInstructions": "how to take (e.g., 1 tablet twice daily)",
  "sideEffects": "common side effects",
  "warnings": "warnings or precautions",
  "storageInstructions": "storage conditions",
  "category": "medicine category (e.g., Antibiotic, Pain Relief, Vitamin)",
  "prescription": "prescription required or not (true/false)"
}''';

  // Calculate medicine potency based on expiry date
  Map<String, dynamic> calculatePotency(String expiryDate) {
    try {
      if (expiryDate == 'Not visible' || expiryDate.isEmpty) {
        return {
          'potency': 0,
          'status': 'Unknown',
          'daysUntilExpiry': null,
          'color': 'grey',
        };
      }

      // Parse expiry date (DD/MM/YYYY)
      final parts = expiryDate.split('/');
      if (parts.length != 3) {
        return {
          'potency': 0,
          'status': 'Invalid Date',
          'daysUntilExpiry': null,
          'color': 'grey',
        };
      }

      final expiry = DateTime(
        int.parse(parts[2]), // year
        int.parse(parts[1]), // month
        int.parse(parts[0]), // day
      );

      final now = DateTime.now();
      final difference = expiry.difference(now).inDays;

      if (difference < 0) {
        // Expired
        return {
          'potency': 0,
          'status': 'Expired',
          'daysUntilExpiry': difference,
          'color': 'red',
          'message': 'Medicine has expired. Dispose safely.',
        };
      } else if (difference <= 30) {
        // Expiring soon
        return {
          'potency': 30 + (difference * 2),
          'status': 'Expiring Soon',
          'daysUntilExpiry': difference,
          'color': 'orange',
          'message': 'Medicine will expire in $difference days.',
        };
      } else if (difference <= 180) {
        // Good condition
        return {
          'potency': 70 + (difference ~/ 6),
          'status': 'Good',
          'daysUntilExpiry': difference,
          'color': 'yellow',
          'message': 'Medicine is in good condition.',
        };
      } else {
        // Excellent condition
        return {
          'potency': 90 + (difference > 365 ? 10 : (difference - 180) ~/ 18),
          'status': 'Excellent',
          'daysUntilExpiry': difference,
          'color': 'green',
          'message': 'Medicine is fresh and safe to use.',
        };
      }
    } catch (e) {
      return {
        'potency': 0,
        'status': 'Error',
        'daysUntilExpiry': null,
        'color': 'grey',
        'error': e.toString(),
      };
    }
  }
}