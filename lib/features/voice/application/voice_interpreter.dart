import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../../../core/errors/app_exception.dart';
import '../../../domain/enums.dart';
import '../domain/category_matcher.dart';
import '../domain/voice_parse_result.dart';
import '../domain/voice_transaction_parser.dart';
import '../domain/wallet_alias_matcher.dart';

/// A *partial* structured interpretation produced by an interpreter.
///
/// Fields are names, not ids: resolving a name to a real wallet or category is
/// the app's job, and an online interpreter must never be able to invent a
/// wallet the user does not own.
@immutable
class InterpretationHint {
  const InterpretationHint({
    this.type,
    this.amountPoisha,
    this.walletName,
    this.toWalletName,
    this.categoryName,
    this.occurredAt,
    this.description,
    this.confidence = 0,
    this.providerLabel = 'On-device rules',
    this.isOnline = false,
  });

  final TransactionType? type;
  final int? amountPoisha;
  final String? walletName;
  final String? toWalletName;
  final String? categoryName;
  final DateTime? occurredAt;
  final String? description;
  final double confidence;
  final String providerLabel;
  final bool isOnline;
}

/// Interprets recognised text into a hint.
abstract class VoiceInterpreter {
  String get id;
  String get label;
  bool get isOnline;

  /// Returns null when the interpreter has nothing to offer, which is normal
  /// for an offline rules interpreter on text it already understood.
  Future<InterpretationHint?> interpret(String text, ParserContext context);
}

/// Offline interpreter. Always available, never sends anything anywhere.
class LocalRuleInterpreter implements VoiceInterpreter {
  const LocalRuleInterpreter();

  @override
  String get id => 'local';

  @override
  String get label => 'On-device rules';

  @override
  bool get isOnline => false;

  @override
  Future<InterpretationHint?> interpret(
    String text,
    ParserContext context,
  ) async {
    final parsed = VoiceTransactionParserAdapter.parse(text, context);
    return InterpretationHint(
      type: parsed.type,
      amountPoisha: parsed.amountPoisha,
      walletName: parsed.walletName,
      toWalletName: parsed.toWalletName,
      categoryName: parsed.categoryName,
      occurredAt: parsed.occurredAt,
      description: parsed.description,
      confidence: parsed.confidence,
      providerLabel: 'On-device rules',
      isOnline: false,
    );
  }
}

/// Thin adapter so this file does not depend on the parser's public surface
/// directly (and so it is easy to swap in a fake in tests).
class VoiceTransactionParserAdapter {
  const VoiceTransactionParserAdapter._();

  static ParsedTransaction parse(String text, ParserContext context) =>
      VoiceTransactionParser(context).parse(text);
}

/// Online interpreter that posts the recognised *text* to a user-controlled
/// endpoint. No key is ever shipped in the app: the bearer token is read from
/// secure storage at request time.
///
/// ## What this does and does not do
/// It does **not** upload audio and it is not a replacement speech recogniser —
/// the device's own engine does the listening. What it does is run the text
/// through a smarter model that the user hosts, which is useful for unusual
/// phrasing and for languages the on-device recogniser mangles. It is clearly
/// labelled as online in the confirmation screen, and the app never calls it
/// unless the user has configured an endpoint *and* selected the online
/// provider in settings.
class OnlineVoiceInterpreter implements VoiceInterpreter {
  OnlineVoiceInterpreter({
    required String endpoint,
    required String languageCode,
    required Future<String?> Function() tokenReader,
    HttpJsonPoster? poster,
    this.timeout = const Duration(seconds: 12),
  }) : _endpoint = endpoint,
       _languageCode = languageCode,
       _tokenReader = tokenReader,
       _poster = poster ?? const DartHttpJsonPoster();

  final String _endpoint;
  final String _languageCode;
  final Future<String?> Function() _tokenReader;
  final HttpJsonPoster _poster;
  final Duration timeout;

  @override
  String get id => 'online';

  @override
  String get label => 'Online interpreter (sends text to your server)';

  @override
  bool get isOnline => true;

  @override
  Future<InterpretationHint?> interpret(
    String text,
    ParserContext context,
  ) async {
    final uri = Uri.tryParse(_endpoint.trim());
    if (uri == null || !uri.hasScheme) {
      throw const ConfigurationException(
        'The online interpreter endpoint is not a valid URL. '
        'Check it in Settings → Voice.',
      );
    }
    final token = await _tokenReader();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final wallets = context.wallets.map((w) => w.name).toList(growable: false);
    final categories = context.categories
        .map((c) => c.name)
        .toList(growable: false);
    final body = jsonEncode(<String, Object?>{
      'text': text,
      'language': _languageCode,
      'today': context.now.toIso8601String(),
      'wallets': wallets,
      'categories': categories,
      'schema': <String, Object?>{
        'type': 'income | expense | transfer',
        'amount': 'number, in BDT',
        'wallet': 'exact wallet name from the list, or null',
        'toWallet': 'exact wallet name for a transfer destination, or null',
        'category': 'exact category name from the list, or null',
        'date': 'ISO-8601 date/time, or null',
        'description': 'short free text, or null',
        'confidence': 'number between 0 and 1',
      },
    });

    final Map<String, Object?> json;
    try {
      json = await _poster
          .post(uri, headers: headers, body: body)
          .timeout(timeout);
    } on TimeoutException {
      throw const ServiceUnavailableException(
        'The online interpreter did not respond in time. The on-device result '
        'is still being used.',
      );
    } on SocketException {
      throw const ServiceUnavailableException(
        'The online interpreter is unreachable. Check your connection, or use '
        'the on-device result.',
      );
    } on HttpStatusException catch (error) {
      throw ServiceUnavailableException(
        'The online interpreter rejected the request '
        '(${error.statusCode}). Check the endpoint and token in Settings → Voice.',
      );
    } on FormatException {
      throw const ServiceUnavailableException(
        'The online interpreter returned something this app could not read.',
      );
    }

    final amount = json['amount'];
    return InterpretationHint(
      type: _typeFrom(json['type']),
      amountPoisha: amount == null
          ? null
          : (amount is num
                ? (amount * 100).round()
                : int.tryParse(
                    amount.toString().replaceAll(RegExp(r'[^0-9]'), ''),
                  )),
      walletName: _stringOrNull(json['wallet']),
      toWalletName: _stringOrNull(json['toWallet']),
      categoryName: _stringOrNull(json['category']),
      occurredAt: DateTime.tryParse(_stringOrNull(json['date']) ?? ''),
      description: _stringOrNull(json['description']),
      confidence: (json['confidence'] as num?)?.toDouble().clamp(0, 1) ?? 0.5,
      providerLabel: 'Online model',
      isOnline: true,
    );
  }

  static TransactionType? _typeFrom(Object? value) {
    if (value == null) return null;
    final text = value.toString().toLowerCase().trim();
    for (final type in TransactionType.values) {
      if (type.name == text) return type;
    }
    return null;
  }

  static String? _stringOrNull(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// Minimal HTTP POST seam so the online interpreter is unit-testable without a
/// server.
abstract class HttpJsonPoster {
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  });
}

class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode';
}

/// `dart:io`-based poster. No third-party HTTP dependency is needed for one
/// POST endpoint.
class DartHttpJsonPoster implements HttpJsonPoster {
  const DartHttpJsonPoster();

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpStatusException(response.statusCode);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

/// Adds [hint] on top of an offline [parsed] result, filling **only** fields the
/// offline parser could not resolve.
///
/// The online interpreter is therefore strictly additive: it can never
/// contradict a wallet or amount the on-device rules already understood, which
/// keeps a bad server response from silently misfiling a transaction.
ParsedTransaction mergeHint(
  ParsedTransaction parsed,
  InterpretationHint hint, {
  required ParserContext context,
}) {
  final unresolved = {...parsed.unresolved};
  var result = parsed;

  if (hint.type != null && parsed.type == null) {
    result = result.copyWith(type: hint.type);
    unresolved.remove(VoiceField.type);
  }
  if (hint.amountPoisha != null &&
      hint.amountPoisha! > 0 &&
      (parsed.amountPoisha == null || parsed.amountPoisha! <= 0)) {
    result = result.copyWith(amountPoisha: hint.amountPoisha);
    unresolved.remove(VoiceField.amount);
    result = result.copyWith(amountSourceText: 'online model');
  }

  if (result.walletId == null && hint.walletName != null) {
    final match = _findWallet(context, hint.walletName!);
    if (match != null) {
      result = result.copyWith(walletId: match.id, walletName: match.name);
      unresolved.remove(VoiceField.wallet);
    }
  }
  if (result.toWalletId == null && hint.toWalletName != null) {
    final match = _findWallet(context, hint.toWalletName!);
    if (match != null) {
      result = result.copyWith(toWalletId: match.id, toWalletName: match.name);
      unresolved.remove(VoiceField.destinationWallet);
    }
  }
  if (result.categoryId == null && hint.categoryName != null) {
    final match = _findCategory(context, hint.categoryName!, result.type);
    if (match != null) {
      result = result.copyWith(categoryId: match.id, categoryName: match.name);
      unresolved.remove(VoiceField.category);
    }
  }
  if (result.occurredAt == null && hint.occurredAt != null) {
    result = result.copyWith(occurredAt: hint.occurredAt);
  }
  if (result.description == null && hint.description != null) {
    result = result.copyWith(description: hint.description);
  }

  return result.copyWith(
    unresolved: unresolved,
    confidence: result.confidence > hint.confidence
        ? result.confidence
        : (result.confidence + hint.confidence) / 2,
    warnings: <String>[
      ...result.warnings,
      'Some fields came from the online model (${hint.providerLabel}). '
          'Please check them before saving.',
    ],
  );
}

WalletCandidate? _findWallet(ParserContext context, String name) {
  final needle = name.trim().toLowerCase();
  for (final wallet in context.wallets) {
    if (wallet.name.trim().toLowerCase() == needle) return wallet;
  }
  return null;
}

CategoryCandidate? _findCategory(
  ParserContext context,
  String name,
  TransactionType? type,
) {
  final needle = name.trim().toLowerCase();
  final expectedKind = switch (type) {
    TransactionType.income => CategoryKind.income,
    TransactionType.expense => CategoryKind.expense,
    _ => null,
  };
  for (final category in context.categories) {
    if (category.name.trim().toLowerCase() != needle) continue;
    if (expectedKind != null && category.kind != expectedKind) continue;
    return category;
  }
  return null;
}
