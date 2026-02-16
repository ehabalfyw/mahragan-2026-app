// app_state.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Global navigator key (shared)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Shared WebView controller reference (public)
WebViewController? globalWebViewController;

// Pending URL to load after login (public)
String? pendingUrlAfterLogin;

// Global login/session flags (public)
bool isUserLoggedIn = false;

