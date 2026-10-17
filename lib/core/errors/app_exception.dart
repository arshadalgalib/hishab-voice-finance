/// Errors raised by the domain/service layer.
///
/// UI code catches these and shows [message] verbatim, so every message must be
/// written for the end user and must never contain raw SQL or stack traces.
library;

/// Base class for problems the user can act on.
sealed class AppException implements Exception {
  const AppException(this.message, {this.field});

  /// Human readable, safe to display.
  final String message;

  /// Optional field key so a form can highlight the offending input.
  final String? field;

  @override
  String toString() => '$runtimeType($message)';
}

/// The submitted data violated a financial or business rule.
class ValidationException extends AppException {
  const ValidationException(super.message, {super.field});
}

/// A referenced row (wallet, category, budget, ...) does not exist any more.
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.field});
}

/// A required external service (speech recogniser, notifications) is
/// unavailable in the current environment.
class ServiceUnavailableException extends AppException {
  const ServiceUnavailableException(super.message, {super.field});
}

/// The operation was understood but is not allowed (e.g. deleting the last
/// wallet while transactions still reference it).
class OperationNotAllowedException extends AppException {
  const OperationNotAllowedException(super.message, {super.field});
}

/// A backup / import file could not be trusted or parsed.
class InvalidFileException extends AppException {
  const InvalidFileException(super.message, {super.field});
}

/// Credentials or configuration required for an online feature are missing.
class ConfigurationException extends AppException {
  const ConfigurationException(super.message, {super.field});
}

/// A new transaction looks like a duplicate of one that already exists.
///
/// The UI turns this into a "Save anyway?" prompt instead of silently writing a
/// second row — the main defence against a double-tapped save button or a
/// duplicated speech callback.
class DuplicateTransactionException extends AppException {
  const DuplicateTransactionException(this.existingId, super.message);

  /// Id of the transaction that already exists.
  final String existingId;
}
