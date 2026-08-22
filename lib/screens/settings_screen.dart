import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/etf.dart';
import '../notification_service.dart';
import '../services/portfolio_repository.dart';

final _dateTimeFmt = DateFormat('dd/MM/yyyy à HH:mm');

class SettingsScreen extends StatefulWidget {
  final PortfolioRepository repository;
  const SettingsScreen({super.key, required this.repository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final TextEditingController _budgetController;
  late final TextEditingController _minOrderController;
  late final TextEditingController _commissionRateController;

  bool? _notificationsEnabled;
  bool? _reminderActuallyScheduled;

  @override
  void initState() {
    super.initState();
    final repo = widget.repository;
    _budgetController = TextEditingController(text: repo.monthlyBudget.toStringAsFixed(0));
    _minOrderController = TextEditingController(text: repo.minOrderAmount.toStringAsFixed(0));
    _commissionRateController = TextEditingController(text: repo.commissionRatePct.toStringAsFixed(2));
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _budgetController.dispose();
    _minOrderController.dispose();
    _commissionRateController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches coming back from the system "Alarms & reminders" / app
    // notification settings screens, which happen outside the app.
    if (state == AppLifecycleState.resumed) _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus() async {
    final notificationsEnabled = await NotificationService.instance.areNotificationsEnabled();
    final scheduled = await NotificationService.instance.isReminderScheduled();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notificationsEnabled;
      _reminderActuallyScheduled = scheduled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final repo = widget.repository;
    final totalPct = repo.etfs.fold<double>(0, (s, e) => s + e.targetPct);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ETF suivis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if ((totalPct - 100).abs() > 0.01 && repo.etfs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'La somme des % cible fait ${totalPct.toStringAsFixed(1)}% (doit faire 100%).',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final etf in repo.etfs)
            Card(
              child: ListTile(
                title: Text(etf.name.isEmpty ? etf.isin : etf.name),
                subtitle: Text('${etf.isin} · ${etf.category}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${etf.targetPct.toStringAsFixed(0)}%'),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openEtfDialog(context, existing: etf),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => repo.removeEtf(etf.isin),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un ETF (par ISIN)'),
            onPressed: () => _openEtfDialog(context),
          ),
          const Divider(height: 32),
          Text('Investissement mensuel', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _budgetController,
            decoration: const InputDecoration(labelText: 'Budget mensuel visé (€)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final value = double.tryParse(v.replaceAll(',', '.'));
              if (value != null) repo.setMonthlyBudget(value);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _minOrderController,
            decoration: const InputDecoration(labelText: 'Montant minimum par ordre BoursoBank (€)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final value = double.tryParse(v.replaceAll(',', '.'));
              if (value != null) repo.setMinOrderAmount(value);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commissionRateController,
            decoration: const InputDecoration(
              labelText: 'Taux de commission BoursoBank (%)',
              helperText: 'Utilisé pour calculer le montant exact à virer (achat + commission).',
              helperMaxLines: 2,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final value = double.tryParse(v.replaceAll(',', '.'));
              if (value != null) repo.setCommissionRatePct(value);
            },
          ),
          const Divider(height: 32),
          Text('Rappel mensuel', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activer le rappel'),
            value: repo.reminderEnabled,
            onChanged: (v) => repo.setReminderEnabled(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Jour du mois'),
            trailing: DropdownButton<int>(
              value: repo.reminderDay,
              items: [
                for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (d) {
                if (d != null) repo.setReminderDay(d);
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Heure du rappel'),
            trailing: TextButton(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: repo.reminderHour, minute: repo.reminderMinute),
                );
                if (picked != null) {
                  await repo.setReminderTime(hour: picked.hour, minute: picked.minute);
                }
              },
              child: Text(TimeOfDay(hour: repo.reminderHour, minute: repo.reminderMinute).format(context)),
            ),
          ),
          if (repo.reminderEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prochain rappel : ${_dateTimeFmt.format(NotificationService.instance.nextOccurrence(
                      dayOfMonth: repo.reminderDay,
                      hour: repo.reminderHour,
                      minute: repo.reminderMinute,
                      alreadyDoneThisMonth: repo.monthPlanComplete,
                    ))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Rafraîchir les diagnostics',
                  onPressed: _refreshNotificationStatus,
                ),
              ],
            ),
            if (_reminderActuallyScheduled != null)
              Text(
                _reminderActuallyScheduled!
                    ? 'Rappel bien enregistré auprès du système ✅'
                    : 'Rappel PAS enregistré auprès du système ⚠️',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _reminderActuallyScheduled!
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
              ),
            if (NotificationService.instance.lastScheduleError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Erreur lors de la dernière programmation : '
                  '${NotificationService.instance.lastScheduleError}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            _NotificationStatusTile(
              label: 'Notifications',
              enabled: _notificationsEnabled,
              onFix: () async {
                await NotificationService.instance.requestPermissions();
                await _refreshNotificationStatus();
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Envoyer une notification de test'),
              onPressed: () => NotificationService.instance.showTestNotification(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openEtfDialog(BuildContext context, {Etf? existing}) async {
    final repo = widget.repository;
    final isinController = TextEditingController(text: existing?.isin ?? '');
    final nameController = TextEditingController(text: existing?.name ?? '');
    final categoryController = TextEditingController(text: existing?.category ?? '');
    final targetController = TextEditingController(
      text: existing != null ? existing.targetPct.toStringAsFixed(0) : '0',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Ajouter un ETF' : 'Modifier un ETF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: isinController,
              enabled: existing == null,
              decoration: const InputDecoration(labelText: 'ISIN'),
              textCapitalization: TextCapitalization.characters,
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nom (libre)'),
            ),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: 'Catégorie (ex. Europe, US, Émergents)'),
            ),
            TextField(
              controller: targetController,
              decoration: const InputDecoration(labelText: '% cible'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (result == true) {
      final isin = isinController.text.trim().toUpperCase();
      if (isin.isEmpty) return;
      final etf = Etf(
        isin: isin,
        name: nameController.text.trim().isEmpty ? isin : nameController.text.trim(),
        category: categoryController.text.trim(),
        targetPct: double.tryParse(targetController.text.replaceAll(',', '.')) ?? 0,
      );
      await repo.addOrUpdateEtf(etf);
    }
  }
}

class _NotificationStatusTile extends StatelessWidget {
  final String label;
  final bool? enabled;
  final VoidCallback onFix;

  const _NotificationStatusTile({
    required this.label,
    required this.enabled,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: enabled == null
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              enabled! ? Icons.check_circle : Icons.warning_amber_rounded,
              color: enabled! ? Colors.green : error,
            ),
      title: Text(label),
      subtitle: enabled == false ? const Text('Désactivé — le rappel ne sonnera pas fiablement.') : null,
      trailing: enabled == false ? TextButton(onPressed: onFix, child: const Text('Activer')) : null,
    );
  }
}
