import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bot_api.dart';
import 'reminder_service.dart';

void main() => runApp(const LeetCodeBotApp());

class LeetCodeBotApp extends StatelessWidget {
  const LeetCodeBotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LeetCode Daily Bot',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfff89f1b)),
      useMaterial3: true,
    ),
    home: const BotHomePage(),
  );
}

class BotHomePage extends StatefulWidget {
  const BotHomePage({super.key});

  @override
  State<BotHomePage> createState() => _BotHomePageState();
}

class _BotHomePageState extends State<BotHomePage> {
  static const _mobileApiUrl = String.fromEnvironment('BOT_API_BASE_URL');
  static const _mobileTokenKey = 'mobile_api_session_token';
  final List<String> _logs = [];
  final _secureStorage = const FlutterSecureStorage();
  bool _isRunning = false;
  String _headline = 'Ready to maintain your streak.';
  Color _headlineColor = Colors.black87;
  bool _remindersEnabled = false;
  String? _mobileToken;

  bool get _canRunLocalBot =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadMobileSession();
  }

  Future<void> _loadMobileSession() async {
    if (_canRunLocalBot || _mobileApiUrl.isEmpty) return;
    final token = await _secureStorage.read(key: _mobileTokenKey);
    if (mounted && token != null && token.isNotEmpty) {
      setState(() => _mobileToken = token);
    }
  }

  Future<void> _runBot() async {
    if (_isRunning) return;
    if (!_canRunLocalBot) {
      await _runMobileBot();
      return;
    }
    final root = Directory.current;
    if (!File('${root.path}${Platform.pathSeparator}.env').existsSync()) {
      setState(() {
        _headline = 'Add your LeetCode cookies first.';
        _headlineColor = Colors.red.shade700;
        _logs
          ..clear()
          ..add(
            'Open Credentials from the side button and save fresh cookies.',
          );
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _headline = 'Running today’s challenge…';
      _headlineColor = Colors.black87;
      _logs
        ..clear()
        ..add('Starting npm start…');
    });

    try {
      final process = await Process.start(
        'npm',
        const ['start'],
        workingDirectory: root.path,
        runInShell: true,
      );
      final output = <String>[];
      final stdoutSub = process.stdout
          .transform(systemEncoding.decoder)
          .listen(output.add);
      final stderrSub = process.stderr
          .transform(systemEncoding.decoder)
          .listen(output.add);
      await Future.wait([
        stdoutSub.asFuture<void>(),
        stderrSub.asFuture<void>(),
      ]);
      final exitCode = await process.exitCode;
      final text = output.join().trim();
      if (!mounted) return;
      setState(() {
        _logs
          ..clear()
          ..addAll(
            text.isEmpty ? ['The bot produced no output.'] : text.split('\n'),
          );
        if (exitCode == 0 && text.contains('Streak maintained.')) {
          _headline = 'Success — your streak is maintained.';
          _headlineColor = Colors.green.shade700;
        } else if (exitCode == 0) {
          _headline = 'Finished. Check the run log.';
          _headlineColor = Colors.orange.shade800;
        } else {
          _headline = 'The bot could not complete.';
          _headlineColor = Colors.red.shade700;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _headline = 'Could not start the bot.';
        _headlineColor = Colors.red.shade700;
        _logs
          ..clear()
          ..add(error.toString());
      });
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _runMobileBot() async {
    if (_mobileApiUrl.isEmpty) {
      setState(() {
        _headline = 'Mobile service has not been configured.';
        _headlineColor = Colors.red.shade700;
        _logs
          ..clear()
          ..add('Build with --dart-define=BOT_API_BASE_URL=https://your-server.example');
      });
      return;
    }
    if (_mobileToken == null && !await _showMobileSignIn()) return;
    setState(() {
      _isRunning = true;
      _headline = 'Running today’s challenge…';
      _headlineColor = Colors.black87;
      _logs
        ..clear()
        ..add('Contacting secure bot service…');
    });
    try {
      final result = await BotApi(_mobileApiUrl).run(_mobileToken!);
      if (!mounted) return;
      setState(() {
        _logs
          ..clear()
          ..addAll(result.logs);
        _headline = result.success ? 'Success — your streak is maintained.' : 'The bot could not complete.';
        _headlineColor = result.success ? Colors.green.shade700 : Colors.red.shade700;
      });
    } on BotApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _headline = error.message;
        _headlineColor = Colors.red.shade700;
        _logs
          ..clear()
          ..add(error.message);
      });
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<bool> _showMobileSignIn() async {
    if (_mobileApiUrl.isEmpty) return false;
    final password = TextEditingController();
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to your bot'),
        content: TextField(
          controller: password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Bot service password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                final token = await BotApi(_mobileApiUrl).signIn(password.text);
                await _secureStorage.write(key: _mobileTokenKey, value: token);
                if (context.mounted) {
                  setState(() => _mobileToken = token);
                  Navigator.pop(context, true);
                }
              } on BotApiException catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    password.dispose();
    return signedIn ?? false;
  }

  String _valueFromInput(String value, String key) {
    final trimmed = value.trim();
    return trimmed.startsWith('$key=')
        ? trimmed.substring(key.length + 1).trim()
        : trimmed;
  }

  Future<void> _showCredentials() async {
    if (!_canRunLocalBot) {
      await _showMobileSignIn();
      return;
    }
    final session = TextEditingController();
    final csrf = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LeetCode credentials',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste fresh values from your logged-in LeetCode browser session. They are saved only in this project’s .env file.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: session,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'LEETCODE_SESSION',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _valueFromInput(value ?? '', 'LEETCODE_SESSION').isEmpty
                      ? 'Session cookie is required.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: csrf,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'LEETCODE_CSRFTOKEN',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _valueFromInput(value ?? '', 'LEETCODE_CSRFTOKEN').isEmpty
                      ? 'CSRF cookie is required.'
                      : null,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    final root = Directory.current;
                    final envFile = File(
                      '${root.path}${Platform.pathSeparator}.env',
                    );
                    final existing = await envFile.exists()
                        ? await envFile.readAsLines()
                        : <String>[];
                    final otherLines = existing
                        .where(
                          (line) =>
                              !line.startsWith('LEETCODE_SESSION=') &&
                              !line.startsWith('LEETCODE_CSRFTOKEN='),
                        )
                        .toList();
                    otherLines.add(
                      'LEETCODE_SESSION=${_valueFromInput(session.text, 'LEETCODE_SESSION')}',
                    );
                    otherLines.add(
                      'LEETCODE_CSRFTOKEN=${_valueFromInput(csrf.text, 'LEETCODE_CSRFTOKEN')}',
                    );
                    await envFile.writeAsString('${otherLines.join('\n')}\n');
                    if (context.mounted) Navigator.pop(context, true);
                  },
                  child: const Text('Save credentials'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    session.dispose();
    csrf.dispose();
    if (saved == true && mounted) {
      setState(() {
        _headline = 'Credentials saved. You can run the bot now.';
        _headlineColor = Colors.green.shade700;
      });
    }
  }

  Future<void> _enableReminders() async {
    try {
      final enabled = await ReminderService.enableDailyReminders();
      if (!mounted) return;
      setState(() => _remindersEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Reminders set for 9:00 AM, 2:00 PM, and 8:00 PM.'
                : 'Notification permission was not granted.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not schedule reminders on this device.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 32),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _showCredentials,
                            icon: const Icon(Icons.key_outlined),
                            label: Text(_canRunLocalBot ? 'Credentials' : 'Connect'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _enableReminders,
                            icon: Icon(
                              _remindersEnabled
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none_outlined,
                            ),
                            label: Text(
                              _remindersEnabled
                                  ? 'Reminders enabled'
                                  : 'Enable 3 daily reminders',
                            ),
                          ),
                        ),
                        Icon(
                          Icons.bolt_rounded,
                          color: colorScheme.primary,
                          size: compact ? 46 : 54,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'LeetCode Daily Bot',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _headline,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: _headlineColor),
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _isRunning ? null : _runBot,
                          icon: _isRunning
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _isRunning
                                ? 'Working…'
                                : _canRunLocalBot
                                ? 'Solve today’s challenge'
                                : 'Solve today’s challenge',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Run log',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: compact ? 180 : 230,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xff101217),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                _logs.isEmpty
                                    ? 'Press the button to start.'
                                    : _logs.join('\n'),
                                style: const TextStyle(
                                  color: Color(0xffd7e0ea),
                                  fontFamily: 'monospace',
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
