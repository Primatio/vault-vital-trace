import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_rppg_collector/main.dart';
import 'package:vault_rppg_collector/models/session_summary.dart';
import 'package:vault_rppg_collector/providers/app_providers.dart';

void main() {
  testWidgets('App boots to home screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsListProvider.overrideWith(_EmptySessions.new),
        ],
        child: const VaultRppgApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Vault rPPG Collector'), findsOneWidget);
    expect(find.text('New Session'), findsOneWidget);
  });
}

class _EmptySessions extends SessionsListNotifier {
  @override
  Future<List<SessionSummary>> build() async => [];
}
