// Client identifiers from the registered Firebase app, never admin credentials.
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError('Firebase for this platform is not configured yet.');
  }

  static const android = FirebaseOptions(
    apiKey: "AIzaSyAh32KcwP9HZEy1eJqi4J9H7z8UdpkIO2k",
    appId: "1:936024798791:android:767712455a775eba4da362",
    messagingSenderId: "936024798791",
    projectId: "jb-fitness-a2dc4",
    storageBucket: "jb-fitness-a2dc4.firebasestorage.app",
  );
}
