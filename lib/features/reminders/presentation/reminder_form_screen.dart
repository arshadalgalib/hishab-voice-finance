import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/app_database.dart';

/// Create / edit form for a bill reminder.
///
/// [reminderId] arrives through go_router's `extra`; `null` means a new one.
class ReminderFormScreen extends ConsumerStatefulWidget {
  const ReminderFormScreen({super.key, this.reminderId});

  final String? reminderId;

  @override
  ConsumerState<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends ConsumerState<ReminderFormScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _daysBeforeController = TextEditingController();
  final _noteController = TextEditingController();

  late DateTime _dueDate;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    _dueDate = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _daysBeforeController.text = '0';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _daysBeforeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Copies the stored reminder into the fields once, before the first build of
  /// any field, so no controller listener fires mid-build.
  void _prefill(ReminderRow reminder) {
    _prefilled = true;
    _dueDate = reminder.dueDate;
    _titleController.text = reminder.title;
    _amountController.text = reminder.amountPoisha == null
        ? ''
        : Money(reminder.amountPoisha!).toStorageString();
    _daysBeforeController.text = reminder.reminderDaysBefore.toString();
    _noteController.text = reminder.note ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.reminderId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit reminder' : 'New reminder')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final reminderId = widget.reminderId;
    if (reminderId == null) {
      return _form(null);
    }
    return AsyncView<List<ReminderRow>>(
      value: ref.watch(remindersProvider),
      loadingMessage: 'Loading reminder…',
      onRetry: () => ref.invalidate(remindersProvider),
      isEmpty: (reminders) =>
          !reminders.any((reminder) => reminder.id == reminderId),
      empty: EmptyState(
        icon: Icons.search_off,
        title: 'Reminder not found',
        message: 'This reminder may have been deleted.',
        action: FilledButton(
          onPressed: () => context.pop(),
          child: const Text('Close'),
        ),
      ),
      builder: (reminders) {
        final reminder = reminders.firstWhere(
          (candidate) => candidate.id == reminderId,
        );
        if (!_prefilled) _prefill(reminder);
        return _form(reminder);
      },
    );
  }

  Widget _form(ReminderRow? existing) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amountController,
            label: 'Amount (optional)',
            helperText: 'Leave empty for a reminder without an amount.',
          ),
          const SizedBox(height: 16),
          DateFieldButton(
            value: _dueDate,
            includeTime: true,
            label: 'Due date',
            onChanged: (value) => setState(() => _dueDate = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _daysBeforeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Remind me days before',
              helperText: '0 reminds you on the due date itself.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(existing),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(ReminderRow? existing) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showAppMessage(context, 'Enter a title for this reminder.');
      return;
    }
    // The amount column is nullable, so an empty field is a valid choice.
    final rawAmount = _amountController.text.trim();
    final amount = rawAmount.isEmpty ? null : Money.tryParse(rawAmount)?.poisha;
    if (rawAmount.isNotEmpty && (amount == null || amount < 0)) {
      showAppMessage(context, 'Enter a valid amount or leave it empty.');
      return;
    }
    final rawDays = _daysBeforeController.text.trim();
    final daysBefore = rawDays.isEmpty ? 0 : int.tryParse(rawDays);
    if (daysBefore == null || daysBefore < 0) {
      showAppMessage(context, 'Remind-before days cannot be negative.');
      return;
    }
    final note = _noteController.text.trim();

    setState(() => _saving = true);
    try {
      final repository = ref.read(reminderRepositoryProvider);
      if (existing == null) {
        await repository.create(
          title: title,
          dueDate: _dueDate,
          amountPoisha: amount,
          note: note,
          reminderDaysBefore: daysBefore,
        );
      } else {
        await repository.update(
          existing.id,
          title: title,
          amountPoisha: amount,
          clearAmount: amount == null,
          dueDate: _dueDate,
          note: note,
          reminderDaysBefore: daysBefore,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }
}
