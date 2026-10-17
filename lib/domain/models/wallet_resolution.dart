import 'package:meta/meta.dart';

/// How a wallet was chosen for a transaction that did not name one.
@immutable
class WalletResolution {
  const WalletResolution({
    required this.reason,
    this.walletId,
    this.walletName,
    this.isConfiguredDefault = false,
    this.isOnlyWallet = false,
  });

  /// No wallet could be chosen; the user must pick one.
  const WalletResolution.unresolved(this.reason)
    : walletId = null,
      walletName = null,
      isConfiguredDefault = false,
      isOnlyWallet = false;

  final String? walletId;
  final String? walletName;

  /// True when the value came from the user's explicit default-wallet setting.
  final bool isConfiguredDefault;

  /// True when there was exactly one candidate, so the choice was forced.
  final bool isOnlyWallet;

  /// Human readable explanation shown next to the picker, e.g.
  /// "Using your default expense wallet".
  final String reason;

  bool get isResolved => walletId != null;
}
