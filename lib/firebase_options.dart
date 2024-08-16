import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return FirebaseOptions(
      apiKey: 'AIzaSyCHU9c-U0IJPQCzdrVXjGZSHjVjVPh5WpI',
      appId: '1:697404764378:android:9168a35c5cf61c348eb5e3',
      messagingSenderId: '697404764378',
      projectId: 'event-information-5ba3f',
      storageBucket: 'event-information-5ba3f.appspot.com',
      // Add other necessary options here
    );
  }
}