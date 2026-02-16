import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'app_state.dart'; // ✅ shared globals
import 'main.dart'; // for WebViewPage class

RemoteMessage? pendingNotification;

/// Background handler
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void handleNotificationNavigation(RemoteMessage message) {
  final logged = message.data['logged'];
  final String targetUrl = "https://mahragan.ngrok.app/notification.php";

  if (!isUserLoggedIn && logged == "1") {
    pendingUrlAfterLogin = targetUrl;

    if (globalWebViewController == null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => const WebViewPage(
            initialUrl: "https://mahragan.ngrok.app/mahragan2026.php",
          ),
        ),
      );
    } else {
      globalWebViewController!.loadRequest(
        Uri.parse("https://mahragan.ngrok.app/mahragan2026.php"),
      );
    }
    return;
  }

  if (isUserLoggedIn && logged == "1" && globalWebViewController != null) {
    globalWebViewController!.loadRequest(Uri.parse(targetUrl));
    return;
  }

  if (globalWebViewController == null) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const WebViewPage(
          initialUrl: "https://mahragan.ngrok.app/mahragan2026.php",
        ),
      ),
    );
  } else {
    globalWebViewController!.loadRequest(
      Uri.parse("https://mahragan.ngrok.app/mahragan2026.php"),
    );
  }
}

/// Optional: initial FCM setup (if you prefer to keep this here)
Future<void> setupFirebaseMessaging() async {
  await Firebase.initializeApp();

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    handleNotificationNavigation(message);
  });

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    handleNotificationNavigation(initialMessage);
  }
}