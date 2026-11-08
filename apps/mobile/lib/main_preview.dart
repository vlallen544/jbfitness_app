import 'package:flutter/material.dart';

import 'main.dart' show JBFitnessApp;
import 'preview/preview_account.dart';
import 'intro_store.dart';

// Separate entry point. Normal builds never import the sample-data transport.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    JBFitnessApp(
      account: createPreviewAccount(),
      preview: true,
      introStore: MemoryIntroStore(),
    ),
  );
}
