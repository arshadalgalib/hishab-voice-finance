import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/date_x.dart';
import '../../../data/local/app_database.dart';

/// The append-only audit trail, newest first.
///
/// Everything here is written by the services themselves; the screen only reads
/// it, so it is a trustworthy record of why a balance changed.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: AsyncView<List<AuditLogRow>>(
        value: ref.watch(auditLogProvider),
        loadingMessage: 'Loading activity…',
        isEmpty: (rows) => rows.isEmpty,
        empty: const EmptyState(
          icon: Icons.history,
          title: 'No activity yet',
          message:
              'Wallet and opening-balance changes, restores and other audited '
              'edits will show up here.',
        ),
        builder: (rows) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) => _AuditTile(row: rows[index]),
        ),
      ),
    );
  }
}

class _AuditTile extends ConsumerWidget {
  const _AuditTile({required this.row});

  final AuditLogRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = _describePayload(ref, row.payloadJson);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          _iconFor(row.entityType),
          size: 20,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(_actionLabel(row.action)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_entityLabel(row.entityType)} · '
            '${formatDateTime(row.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (detail.isNotEmpty) Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: detail.isNotEmpty,
    );
  }

  static IconData _iconFor(String entityType) {
    switch (entityType) {
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'transaction':
        return Icons.receipt_long;
      case 'category':
        return Icons.category_outlined;
      case 'recurring_rule':
        return Icons.repeat;
      case 'database':
        return Icons.storage;
      default:
        return Icons.history;
    }
  }

  static String _entityLabel(String entityType) {
    switch (entityType) {
      case 'wallet':
        return 'Wallet';
      case 'transaction':
        return 'Transaction';
      case 'category':
        return 'Category';
      case 'recurring_rule':
        return 'Recurring rule';
      case 'database':
        return 'Database';
      default:
        return 'Activity';
    }
  }

  static String _actionLabel(String action) {
    switch (action) {
      case 'created':
        return 'Created';
      case 'updated':
        return 'Updated';
      case 'deleted':
        return 'Deleted';
      case 'archived':
        return 'Archived';
      case 'unarchived':
        return 'Unarchived';
      case 'opening_balance_adjusted':
        return 'Opening balance adjusted';
      case 'restored':
        return 'Backup restored';
      case 'posted':
        return 'Posted';
      case 'skipped':
        return 'Skipped';
      default:
        return _humanise(action);
    }
  }

  /// Turns a JSON payload into a single readable line. Money keys are formatted
  /// with the user's own digit/grouping preferences.
  static String _describePayload(WidgetRef ref, String payloadJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } on FormatException {
      return '';
    }
    if (decoded is! Map) return '';
    final formatter = formatterFor(ref);
    final parts = <String>[];
    decoded.forEach((key, value) {
      if (value == null) return;
      final name = _humanise(key.toString().replaceAll('Poisha', ''));
      if (value is int) {
        parts.add('$name ${formatter.format(value)}');
      } else if (value is num) {
        parts.add('$name $value');
      } else if (value is bool) {
        parts.add('$name ${value ? 'yes' : 'no'}');
      } else if (value is String) {
        parts.add('$name $value');
      } else {
        parts.add('$name ${jsonEncode(value)}');
      }
    });
    return parts.join(' · ');
  }

  static String _humanise(String raw) {
    final spaced = raw
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .trim();
    if (spaced.isEmpty) return raw;
    return spaced;
  }
}
