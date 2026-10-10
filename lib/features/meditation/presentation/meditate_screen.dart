import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../application/meditation_session_controller.dart';
import 'widgets/active_session_view.dart';
import 'widgets/session_setup_view.dart';

/// Shows setup until a session starts, then the application-owned session.
class MeditateScreen extends StatelessWidget {
  const MeditateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final session = deps.meditationSessionController;
    return Scaffold(
      appBar: AppBar(title: const Text('Meditate')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) =>
                session.state.status == MeditationSessionStatus.setup
                ? SessionSetupView(
                    session: session,
                    library: deps.localAudioLibrary,
                  )
                : ActiveSessionView(session: session),
          ),
        ),
      ),
    );
  }
}
