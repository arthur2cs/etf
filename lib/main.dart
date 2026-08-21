import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

const _prefKeyEnabled = 'reminder_enabled';
const _prefKeyHour = 'reminder_hour';
const _prefKeyMinute = 'reminder_minute';
const _prefKeyFrequency = 'reminder_frequency';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const ETFReminderApp());
}

class ETFReminderApp extends StatelessWidget {
  const ETFReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ETF Reminder',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const ReminderHomePage(),
    );
  }
}

class ReminderHomePage extends StatefulWidget {
  const ReminderHomePage({super.key});

  @override
  State<ReminderHomePage> createState() => _ReminderHomePageState();
}

class _ReminderHomePageState extends State<ReminderHomePage> {
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  ReminderFrequency _frequency = ReminderFrequency.weekly;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled = prefs.getBool(_prefKeyEnabled) ?? false;
      _time = TimeOfDay(
        hour: prefs.getInt(_prefKeyHour) ?? 9,
        minute: prefs.getInt(_prefKeyMinute) ?? 0,
      );
      _frequency = ReminderFrequency.values[
          prefs.getInt(_prefKeyFrequency) ?? ReminderFrequency.weekly.index];
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, _enabled);
    await prefs.setInt(_prefKeyHour, _time.hour);
    await prefs.setInt(_prefKeyMinute, _time.minute);
    await prefs.setInt(_prefKeyFrequency, _frequency.index);
  }

  Future<void> _applyReminder() async {
    await _savePrefs();
    if (_enabled) {
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Autorise les notifications pour recevoir le rappel.'),
          ),
        );
        return;
      }
      await NotificationService.instance.scheduleReminder(
        hour: _time.hour,
        minute: _time.minute,
        frequency: _frequency,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rappel activé : ${_frequencyLabel(_frequency)} à ${_time.format(context)}')),
      );
    } else {
      await NotificationService.instance.cancelReminder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rappel désactivé.')),
      );
    }
  }

  String _frequencyLabel(ReminderFrequency freq) {
    switch (freq) {
      case ReminderFrequency.daily:
        return 'Tous les jours';
      case ReminderFrequency.weekly:
        return 'Toutes les semaines';
      case ReminderFrequency.monthly:
        return 'Tous les mois';
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Rappel ETF')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reste régulier avec tes investissements',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure un rappel pour ne jamais oublier ton prochain versement sur ton ETF.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Activer le rappel'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          ListTile(
            title: const Text('Fréquence'),
            trailing: DropdownButton<ReminderFrequency>(
              value: _frequency,
              items: ReminderFrequency.values
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(_frequencyLabel(f)),
                      ))
                  .toList(),
              onChanged: (f) {
                if (f != null) setState(() => _frequency = f);
              },
            ),
          ),
          ListTile(
            title: const Text('Heure du rappel'),
            trailing: TextButton(
              onPressed: _pickTime,
              child: Text(_time.format(context)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _applyReminder,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
