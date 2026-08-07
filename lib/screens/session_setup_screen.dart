import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../widgets/status_widgets.dart';
import 'device_connection_screen.dart';
import 'recording_screen.dart';

class SessionSetupScreen extends ConsumerStatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  ConsumerState<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends ConsumerState<SessionSetupScreen> {
  late final TextEditingController _subjectController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(sessionDraftProvider);
    _subjectController = TextEditingController(text: draft.subjectId);
    _notesController = TextEditingController(text: draft.notes);
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _continue() {
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject ID is required')),
      );
      return;
    }

    ref.read(sessionDraftProvider.notifier)
      ..setSubjectId(subject)
      ..setNotes(_notesController.text);

    final polar = ref.read(polarServiceProvider).state;
    if (!polar.isStreaming) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Polar not streaming'),
          content: const Text(
            'Connect a Polar H10 and wait for live heart rate before recording.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceConnectionScreen(),
                  ),
                );
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RecordingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final polar = ref.watch(polarStateProvider).asData?.value ??
        ref.read(polarServiceProvider).state;

    return Scaffold(
      appBar: AppBar(title: const Text('New session')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionStatusChip(state: polar),
          const SizedBox(height: 16),
          const Text(
            'Session details',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Subject ID',
              hintText: 'e.g. subj_042',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'Lighting, posture, protocol notes…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          const StatusBanner(
            message:
                'Recording is fixed at 30 seconds. Keep the phone steady, face centered, and app in the foreground.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _continue,
            child: const Text('Continue to camera'),
          ),
          if (!polar.isStreaming) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceConnectionScreen(),
                  ),
                );
              },
              child: const Text('Connect Polar H10 first'),
            ),
          ],
        ],
      ),
    );
  }
}
