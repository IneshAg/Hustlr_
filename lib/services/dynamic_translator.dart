/// DynamicTranslator
///
/// Provides AI-powered, real-time translation of any runtime string
/// using Gemini 2.5 Flash. Falls back to a curated offline lookup
/// dictionary if the API is unavailable (no network / offline mode).
///
/// **Gemini API key:** Pass at **compile time** only (not from a `.env` file):
/// `flutter run --dart-define=GEMINI_API_KEY=your_key`
/// or add the same `--dart-define` to your Xcode / CI build. If the key is
/// empty, `_fetchGeminiTranslation` is skipped and only the offline map + original
/// English text are used.
///
/// **UI note:** [translateSync] returns immediately (offline/cache) and starts
/// a background Gemini request; widgets do not rebuild when the cache updates.
/// Use [translate] with a [FutureBuilder] if you need the screen to refresh when
/// the API returns.
///
/// Usage:
///   final t = DynamicTranslator.of(context);
///   Text(await t.translate('Heavy Rain'))
library;

import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../core/secrets.dart';

class DynamicTranslator {
  final String locale;
  const DynamicTranslator._(this.locale);

  static DynamicTranslator of(BuildContext context) {
    final tag = Localizations.localeOf(context).languageCode;
    return DynamicTranslator._(tag);
  }
  static String get _apiKey => Secrets.geminiApiKey;
  // ── In-memory cache to avoid re-calling the API for the same string ──────
  static final Map<String, String> _cache = {};

  /// Returns the locale's full language name for prompts
  String get _languageName {
    switch (locale) {
      case 'ta':
        return 'Tamil';
      case 'hi':
        return 'Hindi';
      default:
        return 'English';
    }
  }

  /// Translates a string. Uses cache first, then Gemini API, then offline map.
  Future<String> translate(String? input) async {
    if (input == null || input.trim().isEmpty) return input ?? '';
    if (locale == 'en') return input; // No translation needed

    final cacheKey = '${locale}_$input';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // Try to get a quick offline answer first
    final key = input.trim().toLowerCase();
    final offlineMap = locale == 'ta' ? _ta : locale == 'hi' ? _hi : null;
    final offlineHit = offlineMap?[key] ?? _partialMatch(offlineMap, key);

    // Kick off the Gemini call asynchronously, return offline result immediately
    // if available to avoid any UI blocking.
    if (offlineHit != null) {
      _cache[cacheKey] = offlineHit;
      // Still fire a background refresh to improve future quality
      _fetchGeminiTranslation(input, cacheKey);
      return offlineHit;
    }

    // No offline match — must await Gemini
    final geminiResult = await _fetchGeminiTranslation(input, cacheKey);
    return geminiResult ?? input;
  }

  /// Synchronous fallback used in purely synchronous contexts (e.g. widget build).
  /// Returns offline hit or the original string. Starts async Gemini lookup in background.
  String translateSync(String? input) {
    if (input == null || input.trim().isEmpty) return input ?? '';
    if (locale == 'en') return input;

    final cacheKey = '${locale}_$input';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final key = input.trim().toLowerCase();
    final offlineMap = locale == 'ta' ? _ta : locale == 'hi' ? _hi : null;
    final hit = offlineMap?[key] ?? _partialMatch(offlineMap, key) ?? input;
    _cache[cacheKey] = hit;

    // Fire-and-forget Gemini enrichment in the background
    _fetchGeminiTranslation(input, cacheKey);
    return hit;
  }

  Future<String?> _fetchGeminiTranslation(String input, String cacheKey) async {
    if (_apiKey.isEmpty) return null;
    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'systemInstruction': {
            'parts': [
              {
                'text':
                    'You are a professional translation engine for a gig-worker insurance app called Hustlr. '
                    'Translate the user\'s text to $_languageName. '
                    'Return ONLY the translated text — no explanations, no quotes, no labels. '
                    'Keep any currency symbols (₹), numbers, and proper nouns (Zepto, Swiggy, Hustlr, UPI) unchanged. '
                    'If the input is already in $_languageName, return it unchanged.'
              }
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': input}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0,
            'maxOutputTokens': 256,
          }
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final translated = json['candidates']?[0]?['content']?['parts']?[0]?['text']
            ?.toString()
            .trim();
        if (translated != null && translated.isNotEmpty) {
          _cache[cacheKey] = translated;
          return translated;
        }
      }
    } catch (_) {
      // Silently fall through to offline fallback
    }
    return null;
  }

  /// Tries to find any matching key as a substring for longer API sentences.
  String? _partialMatch(Map<String, String>? map, String input) {
    if (map == null) return null;
    for (final entry in map.entries) {
      if (input.contains(entry.key)) {
        return input.replaceAll(entry.key, entry.value);
      }
    }
    return null;
  }

  // ── Offline Fallback: Tamil ────────────────────────────────────────────────

  static const Map<String, String> _ta = {
    'heavy rain': 'கனமழை',
    'extreme heat': 'கடுமையான வெப்பம்',
    'platform downtime': 'பிளாட்ஃபார்ம் இடைநிறுத்தம்',
    'cyclone': 'சூறாவளி',
    'flooding': 'வெள்ளம்',
    'disruption': 'இடையூறு',
    'adyar dark store zone': 'அடையாறு டார்க் ஸ்டோர் மண்டலம்',
    'velachery dark store zone': 'வேளச்சேரி டார்க் ஸ்டோர் மண்டலம்',
    'tambaram dark store zone': 'தாம்பரம் டார்க் ஸ்டோர் மண்டலம்',
    'anna nagar dark store zone': 'அண்ணா நகர் டார்க் ஸ்டோர் மண்டலம்',
    't nagar dark store zone': 'டி நகர் டார்க் ஸ்டோர் மண்டலம்',
    'omr dark store zone': 'ஓஎம்ஆர் டார்க் ஸ்டோர் மண்டலம்',
    'koramangala dark store zone': 'கோரமங்கலா டார்க் ஸ்டோர் மண்டலம்',
    'electronic city dark store zone': 'எலக்ட்ரானிக் சிட்டி டார்க் ஸ்டோர் மண்டலம்',
    'andheri dark store zone': 'அந்தேரி டார்க் ஸ்டோர் மண்டலம்',
    'bandra dark store zone': 'பாந்திரா டார்க் ஸ்டோர் மண்டலம்',
    'basic shield': 'அடிப்படை கவசம்',
    'standard shield': 'நிலையான கவசம்',
    'full shield': 'முழு கவசம்',
    'basic': 'அடிப்படை',
    'standard': 'நிலையான',
    'full': 'முழு',
    'monday': 'திங்கள்',
    'tuesday': 'செவ்வாய்',
    'wednesday': 'புதன்',
    'thursday': 'வியாழன்',
    'friday': 'வெள்ளி',
    'saturday': 'சனி',
    'sunday': 'ஞாயிறு',
    'earning outlook': 'வருவாய் கண்ணோட்டம்',
    'stable earnings': 'நிலையான வருவாய்',
    'moderate earnings': 'மிதமான வருவாய்',
    'low earnings risk': 'குறைந்த வருவாய் அபாயம்',
    'suggested shift focus': 'பரிந்துரைக்கப்பட்ட ஷிப்ட் கவனம்',
    'morning rush': 'காலை நெரிசல்',
    'evening peak': 'மாலை உச்சம்',
    'lunch hours': 'மதிய நேரம்',
    'night shift': 'இரவு ஷிப்ட்',
    'activate coverage to protect your income during disruptions':
        'இடையூறுகளின்போது உங்கள் வருவாயைப் பாதுகாக்க காப்பீட்டை செயல்படுத்தவும்',
    'your coverage is active': 'உங்கள் காப்பீடு செயலில் உள்ளது',
    'heavy rain expected': 'கனமழை எதிர்பார்க்கப்படுகிறது',
    'disruption forecast': 'இடையூறு முன்னறிவிப்பு',
    'risk of heavy rain on': 'கனமழை அபாயம்',
    'will auto-cover any washout shifts': 'எந்த ஷிப்டையும் தானாக காப்பீடு செய்யும்',
    'coverage starts next monday': 'காப்பீடு அடுத்த திங்கட்கிழமை தொடங்கும்',
    'activate quarterly plan now to secure your income':
        'உங்கள் வருவாயைப் பாதுகாக்க இப்போதே காலாண்டு திட்டத்தை செயல்படுத்தவும்',
    'plan will auto-cover': 'திட்டம் தானாக காப்பீடு செய்யும்',
  };

  // ── Offline Fallback: Hindi ───────────────────────────────────────────────

  static const Map<String, String> _hi = {
    'heavy rain': 'भारी बारिश',
    'extreme heat': 'अत्यधिक गर्मी',
    'platform downtime': 'प्लेटफॉर्म डाउनटाइम',
    'cyclone': 'चक्रवात',
    'flooding': 'बाढ़',
    'disruption': 'व्यवधान',
    'adyar dark store zone': 'अडयार डार्क स्टोर ज़ोन',
    'velachery dark store zone': 'वेलाचेरी डार्क स्टोर ज़ोन',
    'tambaram dark store zone': 'तांबरम डार्क स्टोर ज़ोन',
    'anna nagar dark store zone': 'अन्ना नगर डार्क स्टोर ज़ोन',
    't nagar dark store zone': 'टी नगर डार्क स्टोर ज़ोन',
    'omr dark store zone': 'ओएमआर डार्क स्टोर ज़ोन',
    'koramangala dark store zone': 'कोरमंगला डार्क स्टोर ज़ोन',
    'electronic city dark store zone': 'इलेक्ट्रॉनिक सिटी डार्क स्टोर ज़ोन',
    'andheri dark store zone': 'अंधेरी डार्क स्टोर ज़ोन',
    'bandra dark store zone': 'बांद्रा डार्क स्टोर ज़ोन',
    'basic shield': 'बेसिक शील्ड',
    'standard shield': 'स्टैंडर्ड शील्ड',
    'full shield': 'फुल शील्ड',
    'basic': 'बेसिक',
    'standard': 'स्टैंडर्ड',
    'full': 'फुल',
    'monday': 'सोमवार',
    'tuesday': 'मंगलवार',
    'wednesday': 'बुधवार',
    'thursday': 'गुरुवार',
    'friday': 'शुक्रवार',
    'saturday': 'शनिवार',
    'sunday': 'रविवार',
    'earning outlook': 'कमाई का आउटलुक',
    'stable earnings': 'स्थिर कमाई',
    'moderate earnings': 'मध्यम कमाई',
    'low earnings risk': 'कम कमाई का जोखिम',
    'suggested shift focus': 'सुझाया गया शिफ्ट फोकस',
    'morning rush': 'सुबह की भीड़',
    'evening peak': 'शाम का पीक',
    'lunch hours': 'दोपहर का समय',
    'night shift': 'रात की शिफ्ट',
    'activate coverage to protect your income during disruptions':
        'व्यवधानों के दौरान अपनी कमाई बचाने के लिए कवरेज सक्रिय करें',
    'your coverage is active': 'आपका कवरेज सक्रिय है',
    'heavy rain expected': 'भारी बारिश की संभावना',
    'disruption forecast': 'व्यवधान पूर्वानुमान',
    'risk of heavy rain on': 'भारी बारिश का जोखिम',
    'will auto-cover any washout shifts':
        'किसी भी बर्बाद शिफ्ट को स्वचालित रूप से कवर करेगा',
    'coverage starts next monday': 'कवरेज अगले सोमवार से शुरू होगा',
    'activate quarterly plan now to secure your income':
        'अपनी कमाई सुरक्षित करने के लिए अभी तिमाही योजना सक्रिय करें',
    'plan will auto-cover': 'योजना स्वचालित रूप से कवर करेगी',
  };
}
