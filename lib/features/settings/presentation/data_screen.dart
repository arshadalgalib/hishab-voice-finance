import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../data/services/backup_service.dart';
import '../../../data/services/csv_export_service.dart';

/// Export, backup / restore, storage information and the danger zone.
///
/// Files are always written to the app's own documents directory first and then
/// handed to the system share sheet, so the user decides where they end up.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  final TextEditingController _backupPasswordController =
      TextEditingController();
  final TextEditingController _restorePasswordController =
      TextEditingController();
  final TextEditingController _deleteConfirmController =
      TextEditingController();

  late Future<_StorageInfo> _storageFuture;
  bool _backupAcknowledged = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _storageFuture = _loadStorageInfo();
  }

  @override
  void dispose() {
    _backupPasswordController.dispose();
    _restorePasswordController.dispose();
    _deleteConfirmController.dispose();
    super.dispose();
  }

  Future<_StorageInfo> _loadStorageInfo() async {
    final database = ref.read(appDatabaseProvider);
    final counts = await database.tableCounts();
    final integrity = await database.integrityCheck();
    return _StorageInfo(counts: counts, integrity: integrity);
  }

  void _reloadStorageInfo() {
    setState(() => _storageFuture = _loadStorageInfo());
  }

  Future<void> _exportTransactions() async {
    await _runExport(
      prefix: 'transactions',
      generate: () => ref.read(csvExportServiceProvider).exportTransactions(),
    );
  }

  Future<void> _exportCategoryTotals() async {
    final range = ref.read(currentMonthRangeProvider);
    await _runExport(
      prefix: 'category-totals',
      generate: () =>
          ref.read(csvExportServiceProvider).exportCategoryTotals(range: range),
    );
  }

  Future<void> _runExport({
    required String prefix,
    required Future<String> Function() generate,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final now = ref.read(clockProvider).now();
      final csv = await generate();
      final fileName = CsvExportService.fileName(prefix, now);
      final path = await _writeToDocuments(fileName, csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/csv')],
          subject: fileName,
        ),
      );
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(lastExportAt: now));
      if (!mounted) return;
      showAppMessage(context, 'Exported $fileName.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not export the file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    final password = _backupPasswordController.text;
    setState(() => _busy = true);
    try {
      final now = ref.read(clockProvider).now();
      final text = await ref
          .read(backupServiceProvider)
          .exportToString(password: password.isEmpty ? null : password);
      final fileName = _backupFileName(now);
      final path = await _writeToDocuments(fileName, text);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/json')],
          subject: fileName,
        ),
      );
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(lastBackupAt: now));
      // Do not keep the password the user typed in memory any longer than
      // needed.
      _backupPasswordController.clear();
      if (!mounted) return;
      showAppMessage(
        context,
        password.isEmpty
            ? 'Backup created as readable JSON: $fileName.'
            : 'Encrypted backup created: $fileName.',
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not create the backup.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromBackup() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a backup file',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null) return;
      final contents = utf8.decode(await picked.readAsBytes());
      final password = _restorePasswordController.text;
      final payload = ref
          .read(backupServiceProvider)
          .decode(contents, password: password.isEmpty ? null : password);
      if (!mounted) return;
      final confirmed = await _confirmRestore(payload);
      if (confirmed != true) return;
      if (!mounted) return;
      setState(() => _busy = true);
      final imported = await ref.read(backupServiceProvider).restore(payload);
      _restorePasswordController.clear();
      _reloadStorageInfo();
      if (!mounted) return;
      final total = imported.values.fold<int>(0, (sum, count) => sum + count);
      showAppMessage(context, 'Restore finished: $total row(s) written.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not read that backup file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRestore(BackupPayload payload) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Text(
          'Restoring replaces everything currently stored on this device with '
          'the ${payload.totalRows} row(s) in this backup '
          '(made ${formatDateTime(payload.exportedAt)}). This cannot be undone, so '
          'create a fresh backup first if you are unsure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace everything'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllData() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(appDatabaseProvider).clearAllData();
      _deleteConfirmController.clear();
      _backupAcknowledged = false;
      _reloadStorageInfo();
      if (!mounted) return;
      showAppMessage(context, 'All local data deleted.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not delete the data.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _writeToDocuments(String fileName, String contents) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  static String _backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}';
    return 'hishab-backup-$stamp.json';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data, backup & export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SectionCard(
            title: 'Export',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Spreadsheets open cleanly in Excel, LibreOffice and Google '
                  'Sheets. Amounts are written as plain decimal taka.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _exportTransactions,
                  icon: const Icon(Icons.grid_on),
                  label: const Text('Transactions CSV'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCategoryTotals,
                  icon: const Icon(Icons.pie_chart_outline),
                  label: const Text('Category totals CSV (this month)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Backup',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'A backup contains every wallet, category, transaction, '
                  'budget, goal, reminder and setting. With a password the file '
                  'is encrypted with AES-256-GCM (key derived with '
                  'PBKDF2-HMAC-SHA256); without one it is plain, readable JSON.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _backupPasswordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password (optional)',
                    helperText:
                        'At least 6 characters when set. Keep it safe — it '
                        'cannot be recovered.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _createBackup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Create backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Restore',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Restoring replaces everything currently stored on this '
                  'device. If the backup is password protected, enter the same '
                  'password here first.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _restorePasswordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password (if any)',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restoreFromBackup,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore from backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Storage',
            action: IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _reloadStorageInfo,
              icon: const Icon(Icons.refresh),
            ),
            child: FutureBuilder<_StorageInfo>(
              future: _storageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingView(message: 'Reading storage…');
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return ErrorStateView(
                    message: 'Could not read the local database.',
                    onRetry: _reloadStorageInfo,
                  );
                }
                final info = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledRow(
                      label: 'Database integrity',
                      value: info.integrity.toLowerCase() == 'ok'
                          ? 'ok'
                          : info.integrity,
                      emphasise: true,
                    ),
                    const Divider(height: 24),
                    for (final entry in info.counts.entries)
                      LabeledRow(
                        label: _tableLabel(entry.key),
                        value: entry.value.toString(),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Danger zone',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Deleting all data removes every wallet, category, '
                  'transaction, budget, goal, reminder, loan and setting on '
                  'this device. It cannot be undone.',
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _backupAcknowledged,
                  title: const Text('I have a backup I can restore from'),
                  onChanged: (value) =>
                      setState(() => _backupAcknowledged = value ?? false),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _deleteConfirmController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_busy || !_canDelete) ? null : _deleteAllData,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete all data'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _canDelete =>
      _backupAcknowledged && _deleteConfirmController.text.trim() == 'DELETE';

  static String _tableLabel(String key) {
    switch (key) {
      case 'wallets':
        return 'Wallets';
      case 'categories':
        return 'Categories';
      case 'transactions':
        return 'Transactions';
      case 'budgets':
        return 'Budgets';
      case 'savingsGoals':
        return 'Savings goals';
      case 'goalContributions':
        return 'Goal contributions';
      case 'recurringRules':
        return 'Recurring rules';
      case 'reminders':
        return 'Reminders';
      case 'loans':
        return 'Loans';
      case 'loanPayments':
        return 'Loan payments';
      case 'appSettings':
        return 'Preference rows';
      case 'auditLogs':
        return 'Activity log entries';
      default:
        return key;
    }
  }
}

/// Snapshot of the two maintenance reads shown in the storage card.
class _StorageInfo {
  const _StorageInfo({required this.counts, required this.integrity});

  final Map<String, int> counts;
  final String integrity;
}
