import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_handler.dart';
import 'app_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await _setupFCM();
  runApp(const MahraganApp());
}

Future<void> _setupFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission();
  debugPrint("🔔 Permission: ${settings.authorizationStatus}");
  String? token = await messaging.getToken();
  debugPrint("📱 FCM Token: $token");
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📩 Foreground: ${message.notification?.title}");
  });
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    handleNotificationNavigation(message);
  });
  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) handleNotificationNavigation(initialMessage);
}

class MahraganApp extends StatelessWidget {
  const MahraganApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Mahragan 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
        ),
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, this.initialUrl});
  final String? initialUrl;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  String _chrname = '';
  String _chrid = '';
  bool _isLoading = true;
  bool _isLoggedIn = false;
  int _selectedBottomIndex = 0;
  int _selectedTopIndex = -1;
  String _currentUrl = '';

  int _roleCount = 0;
  String _userRole = '';
  String _playerName = '';
  String _refIdPlayer = '';
  String _gradeIdPlayer = '';
  String _refIdJudge = '';
  String _gradeIdJudge = '';
  String _refIdCoordinator = '';
  String _gradeIdCoordinator = '';
final Map<String, String> _savedPageUrls = {};
  // Pages that are ONE step above login (direct children of 2026.php)
  // When back is pressed on these pages, show logout confirmation
  final List<String> _rootPages = [
    'menu3.php',
    'participantmenuphone.php',
    'judgemenuphone.php',
  ];

  // ============================================================
  // PARENT MAP - Each page knows its parent
  // ============================================================
  // Remove duplicates - keep only UNAMBIGUOUS pages here
Map<String, String> get _pageParents => {
    // Coordinator only flow
    'menu3.php':                          '2026.php',
    'updateandassign.php':                'menu3.php',
    'participants_phoneapp.php':          'updateandassign.php',
    'gradekg_backup_phoneapp.php':        'participants_phoneapp.php',
    'playerpasscode.php':                 'updateandassign.php',
    'players_list.php':                   'updateandassign.php',
    'assignplayer.php':                   'updateandassign.php',
    'groupsubmission.php':                'updateandassign.php',
    'submithymnsonline.php':              'groupsubmission.php',
    'submithymnsonlinelvlt.php':          'groupsubmission.php',
    'chesspingplayers.php':               'updateandassign.php',
    'newcoordinator.php':                 'updateandassign.php',
    'judgespassword.php':                 'updateandassign.php',
    'coordinator_plate_select.php':       'updateandassign.php',
    'gradekg_Backup.php':                 'menu3.php',
    'shritsdtl.php':                      'menu3.php',
    'newjudge.php':                       '2026.php',
   'maincoordinator.php':                '2026.php',
   'view.php':                           '2026.php',
    // Player only flow
    'participantmenuphone.php':           '2026.php',
   'gradekg_Backup_phoneapp.php':        '__role_menu__', // ✅ goes to menu3 if multi-role
    'submitexamtype.php':                 '__role_menu__', // ✅ goes to menu3 if multi-role
    'submitothers.php':                   'submitexamtype.php',
    'submit.php':                         'submitexamtype.php',

    // Judge only flow
    'judgemenuphone.php':                 '2026.php',
    'judgesscheduleonline_phoneapp.php':  'judgesschedulelayout.php',
    'submissions.php':                    'judgesscheduleonline_phoneapp.php',

    // Shared pages
    'spiritualschedules.php':             '__role_menu__',
    'Sportschedule.php':                  '__role_menu__',
    'notification.php':                   '__role_menu__',
    'all3.php':                           '__role_menu__',
    'all3spr.php':                        '__role_menu__',
  };

  // Pages whose parent depends on which role accessed them
  String? _getRoleBasedParent(String basePage) {
    switch (basePage) {

      // judgesschedulelayout.php parent depends on role:
      // coordinator → menu3.php
      // judge       → judgemenuphone.php
      case 'judgesschedulelayout.php':
        // Multi-role or coordinator → menu3.php
        // Single judge → judgemenuphone.php
        if (_userRole == 'judge' && _roleCount == 1) {
          return 'judgemenuphone.php';
        }
        return 'menu3.php';

      // these always go to judgesschedulelayout
      // but judgesschedulelayout itself will route correctly by role
      case 'editjudgeprof_phoneapp.php':
        return 'judgesschedulelayout.php';

      case 'judgesschedulerooms_phoneapp.php':
        return 'judgesschedulelayout.php';
      // ✅ NEW - shared pages go back to view.php if accessed as guest
      // or role menu if accessed while logged in
      case 'spiritualschedules.php':
      case 'Sportschedule.php':
      case 'notification.php':
      case 'all3.php':
      case 'all3spr.php':
        // If not logged in (guest via view.php) → go to view.php
        // If logged in → go to role menu (handled by __role_menu__ in static map)
        if (!_isLoggedIn) {
          return 'view.php';
        }
        return null; // falls through to static map which has __role_menu__
      default:
        return null;
    }
  }

  String _getBasePage(String url) {
    try {
      return Uri.parse(url).path.split('/').last;
    } catch (_) {
      return '';
    }
  }

  Map<String, String> _extractParams(String url) {
    Map<String, String> params = {};
    try {
      params = Map<String, String>.from(Uri.parse(url).queryParameters);
    } catch (_) {}

    // Override with latest known state values
    if (_chrname.isNotEmpty) params['chrname'] = _chrname;
    if (_chrid.isNotEmpty) params['chrid'] = _chrid;
    if (_playerName.isNotEmpty) params['playername'] = _playerName;
    if (_refIdPlayer.isNotEmpty) params['ref_id_player'] = _refIdPlayer;
    if (_gradeIdPlayer.isNotEmpty) params['grade_id_player'] = _gradeIdPlayer;
    if (_refIdJudge.isNotEmpty) params['ref_id_judge'] = _refIdJudge;
    if (_gradeIdJudge.isNotEmpty) params['grade_id_judge'] = _gradeIdJudge;
    if (_refIdCoordinator.isNotEmpty) params['ref_id_coordinator'] = _refIdCoordinator;
    if (_gradeIdCoordinator.isNotEmpty) params['grade_id_coordinator'] = _gradeIdCoordinator;
    if (_roleCount > 0) params['roleCount'] = _roleCount.toString();
    if (_userRole.isNotEmpty) params['role'] = _userRole;
    if (_isLoggedIn) params['logged'] = '1';

    return params;
  }

  String _getRoleMenuUrl() {
    final params = _extractParams(_currentUrl);
if (_roleCount > 1) {
      params['role'] = 'multi';
      params['roleCount'] = _roleCount.toString();
      return Uri.https('mahragan2026.ngrok.app', '/menu3.php', params).toString();
    }

    if (_userRole == 'player') {
      params['roleCount'] = '1';
      params['role'] = 'player';
      return Uri.https('mahragan2026.ngrok.app', '/participantmenuphone.php', params).toString();
    } else if (_userRole == 'judge') {
      params['roleCount'] = '1';
      params['role'] = 'judge';
      return Uri.https('mahragan2026.ngrok.app', '/judgemenuphone.php', params).toString();
    } else {
      params['role'] = _userRole.isNotEmpty ? _userRole : 'coordinator';
      return Uri.https('mahragan2026.ngrok.app', '/menu3.php', params).toString();
    }
  }

  String? _getParentUrl(String currentUrl) {
    final basePage = _getBasePage(currentUrl);

    // Step 1: Check role-based pages first
    final roleBasedParent = _getRoleBasedParent(basePage);
    if (roleBasedParent != null) {
      if (roleBasedParent == '2026.php') {
        return 'https://mahragan2026.ngrok.app/2026.php';
      }
      final params = _extractParams(currentUrl);
      return Uri.https('mahragan2026.ngrok.app', '/$roleBasedParent', params).toString();
    }

    // Step 2: Check static map
    final parentPage = _pageParents[basePage];
    if (parentPage == null) return null;
    if (parentPage == '__role_menu__') return _getRoleMenuUrl();
    if (parentPage == '2026.php') {
      return 'https://mahragan2026.ngrok.app/2026.php';
    }

    final params = _extractParams(currentUrl);
    return Uri.https('mahragan2026.ngrok.app', '/$parentPage', params).toString();
  }

  // Shows logout confirmation dialog
  // Returns true if user confirmed logout
  Future<bool> _showLogoutConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 12),
            Text('Leave App?'),
          ],
        ),
        content: const Text(
          'You are about to go back to the login page.\nDo you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Stay', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _onWillPop() async => await _smartGoBack();

Future<bool> _smartGoBack() async {
    if (_currentUrl.isEmpty) return true;

    final basePage = _getBasePage(_currentUrl);
    final parentValue = _pageParents[basePage];
    final roleBasedParent = _getRoleBasedParent(basePage);
    

    // DEBUG snackbar - remove after testing
   

    // Step 1: Login page = exit app
    if (basePage == '2026.php') {
      return true;
    }

    // Step 2: Root pages = show logout confirmation
    if (_rootPages.contains(basePage)) {
// Special case: if multi-role user is on participantmenuphone or judgemenuphone
      // back should go to menu3.php, not show logout
      if (_roleCount > 1 && basePage != 'menu3.php') {
        final params = _extractParams(_currentUrl);
        params['role'] = 'multi';
        params['roleCount'] = _roleCount.toString();
        final menuUrl = Uri.https('mahragan2026.ngrok.app', '/menu3.php', params).toString();
        await _controller.loadRequest(Uri.parse(menuUrl));
        return false;
      }

      final confirmed = await _showLogoutConfirmation();
      if (confirmed) {
        setState(() {
          _isLoggedIn = false;
          isUserLoggedIn = false;
          _currentUrl = '';
          _userRole = '';
          _chrname = '';
          _chrid = '';
          _playerName = '';
          _refIdPlayer = '';
          _gradeIdPlayer = '';
          _refIdJudge = '';
          _gradeIdJudge = '';
          _refIdCoordinator = '';
          _gradeIdCoordinator = '';
          _roleCount = 0;
           _savedPageUrls.clear();
        });
        await _controller.loadRequest(
            Uri.parse("https://mahragan2026.ngrok.app/2026.php"));
      }
      return false;
    }

    // Step 3: Try role-based parent FIRST
   if (roleBasedParent != null) {
      // ✅ Use saved URL if available, otherwise build from params
      final targetUrl = roleBasedParent == '2026.php'
          ? 'https://mahragan2026.ngrok.app/2026.php'
          : _savedPageUrls.containsKey(roleBasedParent)
              ? _savedPageUrls[roleBasedParent]!   // ← USE SAVED URL
              : Uri.https('mahragan2026.ngrok.app', '/$roleBasedParent',
                  _extractParams(_currentUrl)).toString();
      
      debugPrint("⬅️ RoleBased: $basePage → $roleBasedParent");
      debugPrint("🔗 URL: $targetUrl");
      await _controller.loadRequest(Uri.parse(targetUrl));
      return false;
    }

    // Step 4: Try static map parent
    if (parentValue != null) {
      // ✅ Use saved URL if available
      final targetUrl = parentValue == '__role_menu__'
          ? _getRoleMenuUrl()
          : parentValue == '2026.php'
              ? 'https://mahragan2026.ngrok.app/2026.php'
              : _savedPageUrls.containsKey(parentValue)
                  ? _savedPageUrls[parentValue]!   // ← USE SAVED URL
                  : Uri.https('mahragan2026.ngrok.app', '/$parentValue',
                      _extractParams(_currentUrl)).toString();
      
      debugPrint("⬅️ MapBased: $basePage → $parentValue");
      debugPrint("🔗 URL: $targetUrl");
      await _controller.loadRequest(Uri.parse(targetUrl));
      return false;
    }

    // Step 5: Fallback - go to role menu
    debugPrint("⚠️ No parent found for: $basePage - going to role menu");
    await _controller.loadRequest(Uri.parse(_getRoleMenuUrl()));
    return false;
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(children: [
          Icon(Icons.logout, color: Colors.red),
          SizedBox(width: 12),
          Text('Logout'),
        ]),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isLoggedIn = false;
                isUserLoggedIn = false;
                _currentUrl = '';
                _userRole = '';
                _chrname = '';
                _chrid = '';
                _playerName = '';
                _refIdPlayer = '';
                _gradeIdPlayer = '';
                _refIdJudge = '';
                _gradeIdJudge = '';
                _refIdCoordinator = '';
                _gradeIdCoordinator = '';
                _roleCount = 0;
              });
              _controller.loadRequest(
                  Uri.parse("https://mahragan2026.ngrok.app/2026.php"));
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (url) async {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            final basePage = _getBasePage(url);
if (basePage == '2026.php'|| basePage == 'view.php') {
    setState(() {
      _isLoggedIn = false;
      isUserLoggedIn = false;
      _userRole = '';
      _chrname = '';
      _chrid = '';
      _playerName = '';
      _refIdPlayer = '';
      _gradeIdPlayer = '';
      _refIdJudge = '';
      _gradeIdJudge = '';
      _refIdCoordinator = '';
      _gradeIdCoordinator = '';
      _roleCount = 0;
      _savedPageUrls.clear();
    });
  }

  final List<String> pagesToSave = [
    'judgesschedulelayout.php',
    'judgesscheduleonline_phoneapp.php',
    'updateandassign.php',
    'participants_phoneapp.php',
    'groupsubmission.php',
    'submitexamtype.php',
    'menu3.php',
    'participantmenuphone.php',
    'judgemenuphone.php',
    'view.php',      // ✅ ADD THIS
  ];
  if (pagesToSave.contains(basePage)) {
    _savedPageUrls[basePage] = url;
    debugPrint("💾 Saved URL for $basePage");
  }
            // Prevent WebView from building its own history
            await _controller.runJavaScript('''
              (function() {
                var originalPushState = history.pushState;
                history.pushState = function() {
                  return history.replaceState.apply(this, arguments);
                };
              })();
            ''');

            debugPrint("📄 Current: ${_getBasePage(url)}");

            if (url.contains('filepathA=') || url.contains('filepathB=') || url.contains('filepathC=')) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(child: Text("File uploaded! Add comments and click save.")),
                    ]),
                    backgroundColor: Colors.green[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 7),
                  ),
                );
              }
            }

            if (url.contains('logged=1')) {
              final uri = Uri.parse(url);
              setState(() {
                _isLoggedIn = true;
                isUserLoggedIn = true;
                _chrname = uri.queryParameters['chrname'] ?? _chrname;
                _chrid = uri.queryParameters['chrid'] ?? _chrid;
                _userRole = uri.queryParameters['role'] ?? _userRole;
                _roleCount = int.tryParse(uri.queryParameters['roleCount'] ?? '') ?? _roleCount;
                _playerName = uri.queryParameters['playername'] ?? _playerName;
                _refIdPlayer = uri.queryParameters['ref_id_player'] ?? _refIdPlayer;
                _gradeIdPlayer = uri.queryParameters['grade_id_player'] ?? _gradeIdPlayer;
                _refIdJudge = uri.queryParameters['ref_id_judge'] ?? _refIdJudge;
                _gradeIdJudge = uri.queryParameters['grade_id_judge'] ?? _gradeIdJudge;
                _refIdCoordinator = uri.queryParameters['ref_id_coordinator'] ?? _refIdCoordinator;
                _gradeIdCoordinator = uri.queryParameters['grade_id_coordinator'] ?? _gradeIdCoordinator;
              });

              if (pendingUrlAfterLogin != null) {
                _controller.loadRequest(Uri.parse(pendingUrlAfterLogin!));
                pendingUrlAfterLogin = null;
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (!request.url.contains('.php') &&
                (request.url.endsWith('.pdf') || request.url.endsWith('.mp4') ||
                 request.url.endsWith('.mp3') || request.url.endsWith('.jpg') ||
                 request.url.endsWith('.jpeg') || request.url.endsWith('.png') ||
                 request.url.endsWith('.doc') || request.url.endsWith('.docx'))) {
              launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (error.description.contains('ERR_BLOCKED_BY_ORB') ||
                error.description.contains('net::')) return;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Error: ${error.description}"),
                    backgroundColor: Colors.red[700]),
              );
            }
          },
        ),
      )
      ..clearCache();

    globalWebViewController = _controller;

    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setOnShowFileSelector((params) async {
        final result = await FilePicker.platform.pickFiles(
            allowMultiple: false, type: FileType.any);
        if (result == null || result.files.isEmpty) return [];
        final file = result.files.first;
        if (file.path != null) return ['file://${file.path}'];
        return [];
      });
    }

    _controller.loadRequest(Uri.parse(
        widget.initialUrl ?? "https://mahragan2026.ngrok.app/2026.php"));
  }

  Widget _buildNavItem({
    required IconData icon, required String label,
    required String url, required int index, required bool isBottomNav,
  }) {
    final isSelected = isBottomNav
        ? _selectedBottomIndex == index
        : _selectedTopIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              if (isBottomNav) _selectedBottomIndex = index;
              else _selectedTopIndex = index;
            });
            try { globalWebViewController?.loadRequest(Uri.parse(url)); }
            catch (e) { debugPrint("❌ Error: $e"); }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: const Color(0xFF670d10), width: 2.5)
                  : Border.all(color: Colors.grey[300]!, width: 1),
              boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 4, offset: const Offset(0, 2),
              )],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24,
                    color: isSelected ? const Color(0xFF670d10) : const Color(0xFF092756)),
                const SizedBox(height: 4),
                Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF670d10) : const Color(0xFF092756),
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF670d10), Color(0xFF092756)],
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            tooltip: 'Go Back',
            onPressed: () async {
              await _smartGoBack();
            },
          ),
          title: const Text("Mahragan 2026",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
          centerTitle: true,
          // Only show logout button when logged in
          actions: [
            if (_isLoggedIn)
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
          ],
        ),
        body: Column(
          children: [
            // Only show top nav bar when logged in
            if (_isLoggedIn)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6, offset: const Offset(0, 3),
                  )],
                ),
                child: Row(
                  children: [
                    if (_roleCount > 1)
                      _buildNavItem(
                        icon: Icons.home_rounded, label: 'Home',
                        index: 0, isBottomNav: false,
                        url: Uri.https('mahragan2026.ngrok.app', '/menu3.php', {
                          'chrname': _chrname, 'chrid': _chrid,
                          'playername': _playerName,
                          'ref_id_player': _refIdPlayer, 'grade_id_player': _gradeIdPlayer,
                          'ref_id_judge': _refIdJudge, 'grade_id_judge': _gradeIdJudge,
                          'ref_id_coordinator': _refIdCoordinator,
                          'grade_id_coordinator': _gradeIdCoordinator,
                          'roleCount': _roleCount.toString(), 'role': 'multi', 'logged': '1',
                        }).toString(),
                      ),
                    if (_userRole == 'player')
                      _buildNavItem(
                        icon: Icons.person_rounded, label: 'Main\nMenu',
                        index: 1, isBottomNav: false,
                        url: Uri.https('mahragan2026.ngrok.app', '/participantmenuphone.php', {
                          'chrname': _chrname, 'chrid': _chrid,
                          'playername': _playerName,
                          'ref_id_player': _refIdPlayer, 'grade_id_player': _gradeIdPlayer,
                          'ref_id_judge': _refIdJudge, 'grade_id_judge': _gradeIdJudge,
                          'ref_id_coordinator': _refIdCoordinator,
                          'grade_id_coordinator': _gradeIdCoordinator,
                          'roleCount': '1', 'role': 'player', 'logged': '1',
                        }).toString(),
                      ),
                    if (_userRole == 'coordinator')
                      _buildNavItem(
                        icon: Icons.admin_panel_settings_rounded, label: 'Main\nMenu',
                        index: 1, isBottomNav: false,
                        url: Uri.https('mahragan2026.ngrok.app', '/menu3.php', {
                          'chrname': _chrname, 'chrid': _chrid,
                          'playername': _playerName,
                          'ref_id_player': _refIdPlayer, 'grade_id_player': _gradeIdPlayer,
                          'ref_id_judge': _refIdJudge, 'grade_id_judge': _gradeIdJudge,
                          'ref_id_coordinator': _refIdCoordinator,
                          'grade_id_coordinator': _gradeIdCoordinator,
                          'roleCount': '1', 'role': 'coordinator', 'logged': '1',
                        }).toString(),
                      ),
                    if (_userRole == 'judge')
                      _buildNavItem(
                        icon: Icons.gavel_rounded, label: 'Main\nMenu',
                        index: 1, isBottomNav: false,
                        url: Uri.https('mahragan2026.ngrok.app', '/judgemenuphone.php', {
                          'chrname': _chrname, 'chrid': _chrid,
                          'playername': _playerName,
                          'ref_id_judge': _refIdJudge, 'grade_id_judge': _gradeIdJudge,
                          'ref_id_player': _refIdPlayer, 'grade_id_player': _gradeIdPlayer,
                          'ref_id_coordinator': _refIdCoordinator,
                          'grade_id_coordinator': _gradeIdCoordinator,
                          'roleCount': '1', 'role': 'judge', 'logged': '1',
                        }).toString(),
                      ),
                    _buildNavItem(
                      icon: Icons.notifications_active_rounded, label: 'Notifications',
                      index: 2, isBottomNav: false,
                      url: Uri.https('mahragan2026.ngrok.app', '/notification.php', {
                        'chrname': _chrname, 'chrid': _chrid,
                      }).toString(),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    Container(
                      color: Colors.white.withOpacity(0.9),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF670d10)),
                            ),
                            const SizedBox(height: 16),
                            Text('Loading...',
                                style: TextStyle(color: Colors.grey[700],
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        // Only show bottom nav bar when logged in
        bottomNavigationBar: _isLoggedIn
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8, offset: const Offset(0, -3),
                  )],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _buildNavItem(
                          icon: Icons.church_rounded, label: 'Spiritual\nSchedule',
                          index: 0, isBottomNav: true,
                          url: Uri.https('mahragan2026.ngrok.app', '/spiritualschedules.php', {
                            'chrname': _chrname, 'chrid': _chrid,
                          }).toString(),
                        ),
                        _buildNavItem(
                          icon: Icons.sports_soccer_rounded, label: 'Sports\nSchedule',
                          index: 1, isBottomNav: true,
                          url: Uri.https('mahragan2026.ngrok.app', '/Sportschedule.php', {
                            'chrname': _chrname, 'chrid': _chrid,
                          }).toString(),
                        ),
                        _buildNavItem(
                          icon: Icons.access_time_rounded, label: 'Sport\nHourly',
                          index: 2, isBottomNav: true,
                          url: Uri.https('mahragan2026.ngrok.app', '/all3.php', {
                            'chrname': _chrname, 'chrid': _chrid,
                          }).toString(),
                        ),
                        _buildNavItem(
                          icon: Icons.schedule_rounded, label: 'Spiritual\nHourly',
                          index: 3, isBottomNav: true,
                          url: Uri.https('mahragan2026.ngrok.app', '/all3spr.php', {
                            'chrname': _chrname, 'chrid': _chrid,
                          }).toString(),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}