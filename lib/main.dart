import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => AiAgentProvider()),
        ChangeNotifierProvider(create: (_) => DevToolsProvider()),
      ],
      child: const AiBrowserApp(),
    ),
  );
}

class AiBrowserApp extends StatelessWidget {
  const AiBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    return MaterialApp(
      title: 'Luxor Browser',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: browser.neonColor,
          secondary: Colors.white,
          surface: const Color(0xFF121212),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- DATA MODELS ---

class BrowserTab {
  final String id;
  String url, title;
  bool isIncognito;
  InAppWebViewController? controller;
  Uint8List? thumbnail;
  BrowserTab({required this.id, this.url = "neon://home", this.title = "Start Page", this.isIncognito = false});
}

class HistoryItem {
  final String url, title;
  HistoryItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(url: json['url'] ?? "", title: json['title'] ?? "");
}

class BookmarkItem {
  final String url, title;
  BookmarkItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(url: json['url'] ?? "", title: json['title'] ?? "");
}

class SpeedDialItem {
  final String url, label;
  final int colorValue;
  SpeedDialItem({required this.url, required this.label, required this.colorValue});
  Map<String, dynamic> toJson() => {'url': url, 'label': label, 'color': colorValue};
  factory SpeedDialItem.fromJson(Map<String, dynamic> json) => SpeedDialItem(url: json['url'] ?? "", label: json['label'] ?? "", colorValue: json['color'] ?? 0xFF00FFC2);
}

class UserScript {
  String id, name, code;
  bool active;
  UserScript({required this.id, required this.name, required this.code, this.active = true});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'active': active};
  factory UserScript.fromJson(Map<String, dynamic> json) => UserScript(id: json['id'] ?? "", name: json['name'] ?? "", code: json['code'] ?? "", active: json['active'] ?? true);
}

// --- PROVIDERS ---

class DevToolsProvider extends ChangeNotifier {
  List<String> consoleLogs = [];
  void addLog(String message, ConsoleMessageLevel level) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final levelName = level.toString().split('.').last.toUpperCase();
    consoleLogs.add("[$timestamp] $levelName: $message");
    notifyListeners();
  }
  void clearLogs() { consoleLogs.clear(); notifyListeners(); }
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  List<HistoryItem> history = [];
  List<BookmarkItem> bookmarks = [];
  List<String> downloads = [];
  List<UserScript> userScripts = [];
  List<SpeedDialItem> speedDials = [];
  
  String searchEngine = "https://www.google.com/search?q=";
  String customUserAgent = "";
  bool isDesktopMode = false, isAdBlockEnabled = true, isForceDarkWeb = false, isJsEnabled = true, isImagesEnabled = true;
  bool isBiometricEnabled = false, isZenMode = false, isGameMode = false, isLocked = true;
  int blockedAdsCount = 0;
  Color neonColor = const Color(0xFFFFD700); // Luxor Gold

  double progress = 0;
  bool isSecure = true, isMenuOpen = false, showFindBar = false, showAiSidebar = false, showTabGrid = false;
  bool isMediaPlaying = false;
  SslCertificate? sslCertificate;
  
  TextEditingController urlController = TextEditingController(), findController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _flutterTts = FlutterTts();
  final LocalAuthentication auth = LocalAuthentication();
  bool isSpeaking = false;

  BrowserProvider() { _loadData(); _addNewTab(); _initTts(); }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      javaScriptEnabled: isJsEnabled,
      loadsImagesAutomatically: isImagesEnabled,
      cacheEnabled: !currentTab.isIncognito,
      domStorageEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
      supportMultipleWindows: true,
      disableHorizontalScroll: false,
      disableVerticalScroll: false,
      hardwareAcceleration: true,
      userAgent: customUserAgent.isNotEmpty ? customUserAgent : (isDesktopMode ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" : "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
    );
  }

  Future<void> _initTts() async { await _flutterTts.setLanguage("en-US"); await _flutterTts.setSpeechRate(0.5); _flutterTts.setCompletionHandler(() { isSpeaking = false; notifyListeners(); }); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    isForceDarkWeb = prefs.getBool('forceDark') ?? false;
    isJsEnabled = prefs.getBool('jsEnabled') ?? true;
    isImagesEnabled = prefs.getBool('imagesEnabled') ?? true;
    isBiometricEnabled = prefs.getBool('biometric') ?? false;
    blockedAdsCount = prefs.getInt('blockedAds') ?? 0;
    int? colorValue = prefs.getInt('neonColor'); if (colorValue != null) neonColor = Color(colorValue);
    
    history = (prefs.getStringList('history') ?? []).map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    bookmarks = (prefs.getStringList('bookmarks') ?? []).map((e) => BookmarkItem.fromJson(jsonDecode(e))).toList();
    downloads = prefs.getStringList('downloads') ?? [];
    userScripts = (prefs.getStringList('userScripts') ?? []).map((e) => UserScript.fromJson(jsonDecode(e))).toList();
    
    final sd = prefs.getStringList('speedDials');
    if (sd != null && sd.isNotEmpty) {
      speedDials = sd.map((e) => SpeedDialItem.fromJson(jsonDecode(e))).toList();
    } else {
      speedDials = [
        SpeedDialItem(url: "https://google.com", label: "Google", colorValue: Colors.blue.value),
        SpeedDialItem(url: "https://youtube.com", label: "YouTube", colorValue: Colors.red.value),
        SpeedDialItem(url: "https://github.com", label: "GitHub", colorValue: Colors.white.value),
      ];
    }
    isLocked = isBiometricEnabled;
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('searchEngine', searchEngine);
    prefs.setBool('adBlock', isAdBlockEnabled);
    prefs.setBool('forceDark', isForceDarkWeb);
    prefs.setBool('jsEnabled', isJsEnabled);
    prefs.setBool('imagesEnabled', isImagesEnabled);
    prefs.setBool('biometric', isBiometricEnabled);
    prefs.setInt('blockedAds', blockedAdsCount);
    prefs.setInt('neonColor', neonColor.value);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('bookmarks', bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('downloads', downloads);
    prefs.setStringList('userScripts', userScripts.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('speedDials', speedDials.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _addNewTab([String url = "neon://home", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
    showTabGrid = false;
    _updateState();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
      _updateState();
      notifyListeners();
    } else {
      loadUrl("neon://home");
    }
  }

  void switchTab(int index) {
    currentTabIndex = index;
    showTabGrid = false;
    _updateState();
    notifyListeners();
  }

  void toggleTabGrid() async {
    if (!showTabGrid) {
      try { currentTab.thumbnail = await currentTab.controller?.takeScreenshot(); } catch (e) {}
    }
    showTabGrid = !showTabGrid;
    notifyListeners();
  }

  void _updateState() {
    urlController.text = currentTab.url == "neon://home" ? "" : currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    progress = 0;
    showFindBar = false;
    sslCertificate = null;
    isMediaPlaying = false;
  }

  void setController(InAppWebViewController c) => currentTab.controller = c;

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url == "neon://home" ? "" : url;
    isSecure = url.startsWith("https://");
    isMediaPlaying = (url.contains("youtube") || url.contains("video") || url.contains("spotify"));
    notifyListeners();
  }

  void loadUrl(String url) {
    // Handle empty or null URL
    if (url.trim().isEmpty) {
      updateUrl("neon://home");
      notifyListeners();
      return;
    }

    url = url.trim();

    // Handle home page
    if (url == "home" || url == "neon://home" || url == "about:home") {
      updateUrl("neon://home");
      notifyListeners();
      return;
    }

    // Handle special URLs
    if (url.startsWith("neon://")) {
      updateUrl(url);
      notifyListeners();
      return;
    }

    // Check if URL already has protocol
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      // Check if it looks like a search query (contains spaces) or a URL (contains dots)
      if (url.contains(" ") || !url.contains(".")) {
        // This is a search query
        String encodedQuery = Uri.encodeComponent(url);
        url = "$searchEngine$encodedQuery";
      } else {
        // This is a URL without protocol
        url = "https://$url";
      }
    }

    // IMPORTANT: Update the tab URL BEFORE notifying listeners
    // This ensures WebView is shown instead of StartPage
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");

    // Try to load URL if controller exists
    if (currentTab.controller != null) {
      try {
        final uri = WebUri(url);
        currentTab.controller!.loadUrl(urlRequest: URLRequest(url: uri));
      } catch (e) {
        // Fallback to search if URL parsing fails
        String encodedQuery = Uri.encodeComponent(url);
        final searchUrl = "$searchEngine$encodedQuery";
        currentTab.url = searchUrl;
        final searchUri = WebUri(searchUrl);
        currentTab.controller!.loadUrl(urlRequest: URLRequest(url: searchUri));
      }
    }
    // If controller is null, WebView will be created with initialUrlRequest

    notifyListeners();
  }

  void toggleMenu() { isMenuOpen = !isMenuOpen; notifyListeners(); }
  void toggleZenMode() { isZenMode = !isZenMode; notifyListeners(); }
  void toggleAiSidebar() { showAiSidebar = !showAiSidebar; notifyListeners(); }
  void toggleGameMode() {
    isGameMode = !isGameMode;
    if (isGameMode) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      WakelockPlus.enable();
      isZenMode = true;
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      WakelockPlus.disable();
      isZenMode = false;
    }
    notifyListeners();
  }

  void swipeTab(bool isLeft) {
    if (isLeft) { if (currentTabIndex > 0) switchTab(currentTabIndex - 1); } 
    else { if (currentTabIndex < tabs.length - 1) switchTab(currentTabIndex + 1); }
  }

  void panicButton() {
    tabs.removeWhere((t) => t.isIncognito);
    if (tabs.isEmpty) _addNewTab();
    else currentTabIndex = 0;
    loadUrl("neon://home");
    notifyListeners();
  }

  Future<void> checkBiometricLock(BuildContext context) async {
    if (!isBiometricEnabled) { isLocked = false; notifyListeners(); return; }
    try {
      if (await auth.authenticate(localizedReason: 'Unlock Luxor Browser', options: const AuthenticationOptions(stickyAuth: true))) {
        isLocked = false;
        notifyListeners();
      }
    } catch (e) {}
  }

  void toggleBiometric() { isBiometricEnabled = !isBiometricEnabled; _saveData(); notifyListeners(); }
  void toggleBookmark() { if (currentTab.url == "neon://home") return; final idx = bookmarks.indexWhere((b) => b.url == currentTab.url); if (idx != -1) bookmarks.removeAt(idx); else bookmarks.insert(0, BookmarkItem(url: currentTab.url, title: currentTab.title)); _saveData(); notifyListeners(); }
  bool isBookmarked() { return bookmarks.any((b) => b.url == currentTab.url); }
  void addDownload(String f) { downloads.insert(0, "${DateTime.now().toString().substring(0,16)} - $f"); _saveData(); }
  void incrementAdsBlocked() { blockedAdsCount++; if (blockedAdsCount % 5 == 0) _saveData(); notifyListeners(); }
  void findInPage(String t) { if (t.isEmpty) currentTab.controller?.clearMatches(); else currentTab.controller?.findAllAsync(find: t); }
  void findNext() => currentTab.controller?.findNext(forward: true);
  void findPrev() => currentTab.controller?.findNext(forward: false);
  void toggleFindBar() { showFindBar = !showFindBar; if (!showFindBar) currentTab.controller?.clearMatches(); notifyListeners(); }
  void toggleReaderMode() { String js = """(function(){var p=document.getElementsByTagName('p');var txt='';for(var i=0;i<p.length;i++)txt+='<p>'+p[i].innerHTML+'</p>';document.body.innerHTML='<div style=\"max-width:800px;margin:0 auto;padding:20px;font-family:sans-serif;line-height:1.6;color:#e0e0e0;background:#121212;\'>'+txt+'</div>';document.body.style.backgroundColor='#121212';})();"""; currentTab.controller?.evaluateJavascript(source: js); toggleMenu(); }
  void toggleDesktopMode() async { isDesktopMode = !isDesktopMode; await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleAdBlock() async { isAdBlockEnabled = !isAdBlockEnabled; await _saveData(); reload(); notifyListeners(); }
  void toggleForceDark() async { isForceDarkWeb = !isForceDarkWeb; await _saveData(); reload(); notifyListeners(); }
  void toggleJs() async { isJsEnabled = !isJsEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleDataSaver() async { isImagesEnabled = !isImagesEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void setSearchEngine(String url) { searchEngine = url; _saveData(); notifyListeners(); }
  void clearData() async { await currentTab.controller?.clearCache(); await CookieManager.instance().deleteAllCookies(); history.clear(); downloads.clear(); await _saveData(); notifyListeners(); }
  void changeTheme(Color color) { neonColor = color; _saveData(); notifyListeners(); }

  void addUserScript(String n, String c) { userScripts.add(UserScript(id: const Uuid().v4(), name: n, code: c)); _saveData(); notifyListeners(); }
  void toggleUserScript(String id) { final s = userScripts.firstWhere((e) => e.id == id); s.active = !s.active; _saveData(); reload(); notifyListeners(); }
  void deleteUserScript(String id) { userScripts.removeWhere((e) => e.id == id); _saveData(); notifyListeners(); }
  void toggleTts() async { if (isSpeaking) { await _flutterTts.stop(); isSpeaking = false; } else { final text = await currentTab.controller?.evaluateJavascript(source: "document.body.innerText"); if (text != null && text.toString().isNotEmpty) { isSpeaking = true; await _flutterTts.speak(text.toString()); } } notifyListeners(); }

  void injectScripts(InAppWebViewController c) {
    if (isAdBlockEnabled) c.evaluateJavascript(source: "(function(){var b=0;['.ad','.ads','.advertisement','iframe[src*=\"ads\"]','[id^=\"google_ads\"]'].forEach(s=>{var e=document.querySelectorAll(s);if(e.length>0){b+=e.length;e.forEach(x=>x.style.display='none');}});if(b>0)console.log('BLOCKED_ADS:'+b);})();");
    if (isForceDarkWeb) c.evaluateJavascript(source: "(function(){var s=document.createElement('style');s.innerHTML='html{filter:invert(1) hue-rotate(180deg)!important;}img,video,iframe,canvas{filter:invert(1) hue-rotate(180deg)!important;}';document.head.appendChild(s);})();");
    for (var s in userScripts) { if (s.active) c.evaluateJavascript(source: "(function(){ try { ${s.code} } catch(e) { console.log('UserScript Error'); } })();"); }
  }

  Future<void> savePageOffline(BuildContext ctx) async { 
    try { 
      final temp = await getTemporaryDirectory();
      final path = "${temp.path}/offline_${DateTime.now().millisecondsSinceEpoch}.mht";
      await currentTab.controller?.saveWebArchive(filePath: path, autoname: false); 
      addDownload("Archive: $path"); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Saved Offline")));
    } catch (e) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Failed to save"))); } 
  } 
  
  Future<List<String>> sniffMedia() async { final r = await currentTab.controller?.evaluateJavascript(source: "(function(){var v=document.getElementsByTagName('video'),a=document.getElementsByTagName('audio'),l=[];for(var i=0;i<v.length;i++)if(v[i].src)l.push(v[i].src);for(var i=0;i<a.length;i++)if(a[i].src)l.push(a[i].src);return l;})();"); return r != null ? (r as List).map((e) => e.toString()).toList() : []; } 
  void startVoice(BuildContext ctx) async { if (await Permission.microphone.request().isGranted && await _speech.initialize()) _speech.listen(onResult: (r) { if (r.finalResult) loadUrl(r.recognizedWords); }); } 
  void addToHistory(String u, String? t) { if (!currentTab.isIncognito && u != "neon://home" && u != "about:blank" && u.isNotEmpty) { if (history.isEmpty || history.first.url != u) { history.insert(0, HistoryItem(url: u, title: t ?? "Unknown")); if (history.length > 50) history.removeLast(); _saveData(); } } } 
  Future<void> viewSource(BuildContext ctx) async { final h = await currentTab.controller?.getHtml(); if (h != null) Navigator.push(ctx, MaterialPageRoute(builder: (_) => SourceViewerPage(html: h))); } 
  Future<void> shareScreenshot(BuildContext ctx) async { try { final i = await currentTab.controller?.takeScreenshot(); if (i == null) return; final t = await getTemporaryDirectory(); final f = File('${t.path}/shot_${DateTime.now().millisecondsSinceEpoch}.png'); await f.writeAsBytes(i); await Share.shareXFiles([XFile(f.path)]); } catch (e) {} } 
  void setCustomUA(String ua) async { customUserAgent = ua; await currentTab.controller?.setSettings(settings: getSettings()); currentTab.controller?.reload(); notifyListeners(); } 
  void updateSSL(SslCertificate? s) { sslCertificate = s; notifyListeners(); } 
  void goBack() => currentTab.controller?.goBack(); 
  void goForward() => currentTab.controller?.goForward(); 
  void reload() => currentTab.controller?.reload(); 
  void printPage() async { await currentTab.controller?.printCurrentPage(); } 
  
  Future<void> exportData(BuildContext ctx) async { final d = {'history': history.map((e) => e.toJson()).toList(), 'bookmarks': bookmarks.map((e) => e.toJson()).toList(), 'speedDials': speedDials.map((e) => e.toJson()).toList()}; await Share.share(jsonEncode(d)); } 
  Future<void> importData(BuildContext ctx, String s) async { try { final d = jsonDecode(s); if (d['history'] != null) history = (d['history'] as List).map((e) => HistoryItem.fromJson(e)).toList(); if (d['bookmarks'] != null) bookmarks = (d['bookmarks'] as List).map((e) => BookmarkItem.fromJson(e)).toList(); if (d['speedDials'] != null) speedDials = (d['speedDials'] as List).map((e) => SpeedDialItem.fromJson(e)).toList(); await _saveData(); notifyListeners(); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Restored"))); } catch (e) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Import Error"))); } } 
  void factoryReset() async { final p = await SharedPreferences.getInstance(); await p.clear(); _loadData(); notifyListeners(); } 
  void addSpeedDial(String label, String url) { speedDials.add(SpeedDialItem(url: url, label: label, colorValue: Colors.primaries[speedDials.length % Colors.primaries.length].value)); _saveData(); notifyListeners(); } 
  void removeSpeedDial(int index) { speedDials.removeAt(index); _saveData(); notifyListeners(); }
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Luxor AI Ready.", isUser: false)];
  bool isThinking = false;
  void sendMessage(String text, BrowserProvider b) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    String resp = "Processed.";
    if (text.toLowerCase().contains("game")) { b.toggleGameMode(); resp = "Game Mode toggled."; }
    else if (text.toLowerCase().contains("home")) { b.loadUrl("neon://home"); resp = "Going Home."; }
    else { resp = "I can control settings or help you browse."; }
    messages.add(ChatMessage(text: resp, isUser: false));
    isThinking = false; notifyListeners();
  }
}

class ChatMessage { final String text; final bool isUser; ChatMessage({required this.text, required this.isUser}); }

// --- UI COMPONENTS ---

class BrowserHomePage extends StatefulWidget { const BrowserHomePage({super.key}); @override State<BrowserHomePage> createState() => _BrowserHomePageState(); } 
class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _menuController; late Animation<double> _menuScale; late PullToRefreshController _pullToRefreshController;
  late AnimationController _visualizerController;
  
  @override void initState() { 
    super.initState(); 
    WidgetsBinding.instance.addObserver(this);
    _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150)); 
    _menuScale = CurvedAnimation(parent: _menuController, curve: Curves.easeOutBack); 
    _pullToRefreshController = PullToRefreshController(settings: PullToRefreshSettings(color: const Color(0xFF00FFC2), backgroundColor: Colors.black), onRefresh: () async { final b = Provider.of<BrowserProvider>(context, listen: false); if (b.currentTab.url != "neon://home") b.reload(); _pullToRefreshController.endRefreshing(); }); 
    _visualizerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => Provider.of<BrowserProvider>(context, listen: false).checkBiometricLock(context));
  }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _menuController.dispose(); _visualizerController.dispose(); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if(state == AppLifecycleState.paused) Provider.of<BrowserProvider>(context, listen: false).isLocked = true; else if(state == AppLifecycleState.resumed) Provider.of<BrowserProvider>(context, listen: false).checkBiometricLock(context); }

  @override Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context); final devTools = Provider.of<DevToolsProvider>(context);
    if (browser.isBiometricEnabled && browser.isLocked) return const LockScreen();
    if (browser.isMenuOpen) _menuController.forward(); else _menuController.reverse();
    if (browser.showTabGrid) return TabGridPage(browser: browser);
    
    return Scaffold(resizeToAvoidBottomInset: false, backgroundColor: Colors.black, body: Stack(children: [
      AnimatedContainer(duration: const Duration(milliseconds: 300), width: browser.showAiSidebar ? MediaQuery.of(context).size.width * 0.7 : MediaQuery.of(context).size.width, child: Column(children: [
        Expanded(child: browser.currentTab.url == "neon://home" ? StartPage(browser: browser) : InAppWebView(key: ValueKey(browser.currentTab.id), initialUrlRequest: URLRequest(url: WebUri(browser.currentTab.url)), initialSettings: browser.getSettings(), pullToRefreshController: _pullToRefreshController, onWebViewCreated: (c) => browser.setController(c), onLoadStart: (c, url) => browser.updateUrl(url.toString()), onLoadStop: (c, url) async { browser.progress = 1.0; browser.updateUrl(url.toString()); browser.injectScripts(c); browser.addToHistory(url.toString(), await c.getTitle()); browser.updateSSL(await c.getCertificate()); }, onProgressChanged: (c, p) => browser.progress = p / 100, onConsoleMessage: (c, m) { if (m.message.startsWith("BLOCKED_ADS:")) browser.incrementAdsBlocked(); devTools.addLog(m.message, m.messageLevel); })),
        if (!browser.isZenMode) const SizedBox(height: 80),
      ])),
      if (browser.progress < 1.0 && browser.currentTab.url != "neon://home") Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(value: browser.progress, minHeight: 2, color: browser.neonColor, backgroundColor: Colors.transparent)),
      AnimatedPositioned(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, right: browser.showAiSidebar ? 0 : -300, top: 0, bottom: 0, width: MediaQuery.of(context).size.width * 0.75, child: const GlassBox(borderRadius: 0, padding: EdgeInsets.only(top: 40), child: AiSidebar())),
      Positioned(bottom: 90, left: 20, right: 20, child: ScaleTransition(scale: _menuScale, alignment: Alignment.bottomCenter, child: GlassBox(child: _buildGridMenu(context, browser)))),
      if (browser.showFindBar) Positioned(bottom: browser.isZenMode ? 20 : 140, left: 20, right: 20, child: GlassBox(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: TextField(controller: browser.findController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Find...", border: InputBorder.none), onChanged: (v) => browser.findInPage(v))), IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: browser.findPrev), IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: browser.findNext), IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: browser.toggleFindBar)]))),
      if (!browser.showAiSidebar && !browser.isZenMode) AnimatedPositioned(duration: const Duration(milliseconds: 200), bottom: 20, left: 20, right: 20, child: GestureDetector(
        onHorizontalDragEnd: (d) { if (d.primaryVelocity! > 0) browser.swipeTab(true); else if (d.primaryVelocity! < 0) browser.swipeTab(false); },
        child: GlassBox(borderRadius: 50, padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5), child: Row(children: [
          _circleBtn(browser.isMenuOpen ? Icons.close : Iconsax.category, () => browser.toggleMenu()), const SizedBox(width: 8),
          Expanded(child: GestureDetector(onTap: () => _showSearch(context, browser), child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)), alignment: Alignment.centerLeft, child: Row(children: [Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.green : Colors.red), const SizedBox(width: 8), Expanded(child: Text(browser.currentTab.url == "neon://home" ? "Search..." : browser.currentTab.url.replaceFirst("https://", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)), if (browser.currentTab.url != "neon://home") GestureDetector(onTap: () => browser.toggleBookmark(), child: Icon(browser.isBookmarked() ? Iconsax.star1 : Iconsax.star, size: 14, color: browser.isBookmarked() ? browser.neonColor : Colors.white30)), const SizedBox(width: 8), GestureDetector(onTap: () => browser.toggleTabGrid(), child: Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(5)), child: Text("${browser.tabs.length}", style: const TextStyle(fontSize: 10, color: Colors.white))))])))),
          const SizedBox(width: 8), _circleBtn(browser.isSpeaking ? Icons.stop : Iconsax.magic_star, () => browser.isSpeaking ? browser.toggleTts() : browser.toggleAiSidebar(), color: browser.neonColor),
        ]))
      )),
      if (browser.isMediaPlaying && !browser.isZenMode) Positioned(bottom: 0, left: 0, right: 0, height: 2, child: AnimatedBuilder(animation: _visualizerController, builder: (context, child) => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(20, (i) => Container(width: 5, height: 2 + (Random().nextDouble() * 10 * _visualizerController.value), color: browser.neonColor.withOpacity(0.5), margin: const EdgeInsets.symmetric(horizontal: 1)))))),
      if (browser.isZenMode) Positioned(bottom: 20, right: 20, child: FloatingActionButton.small(backgroundColor: Colors.white10, child: Icon(browser.isGameMode ? Icons.videogame_asset_off : Icons.expand_less, color: Colors.white), onPressed: () => browser.isGameMode ? browser.toggleGameMode() : browser.toggleZenMode()))
    ]));
  }
  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(width: 44, height: 44, alignment: Alignment.center, child: Icon(icon, color: color, size: 22)));
  Widget _buildGridMenu(BuildContext context, BrowserProvider b) => GridView.count(shrinkWrap: true, crossAxisCount: 5, mainAxisSpacing: 15, padding: const EdgeInsets.all(16), children: [
    _menuItem(Iconsax.arrow_left_2, "Back", b.goBack), _menuItem(Iconsax.arrow_right_3, "Fwd", b.goForward), _menuItem(Iconsax.refresh, "Reload", b.reload), _menuItem(Iconsax.printer, "Print", () { b.toggleMenu(); b.printPage(); }), _menuItem(Iconsax.game, "Game", () { b.toggleGameMode(); b.toggleMenu(); }), _menuItem(Iconsax.code_circle, "Script", () { b.toggleMenu(); _showScriptManager(context, b); }), _menuItem(Iconsax.volume_high, "Read", () { b.toggleTts(); b.toggleMenu(); }), _menuItem(Iconsax.document_download, "Files", () { b.toggleMenu(); _showDownloads(context, b); }), _menuItem(Iconsax.setting, "Settings", () { b.toggleMenu(); _showSettingsModal(context, b); }), _menuItem(Iconsax.bookmark, "Saved", () { b.toggleMenu(); _showBookmarks(context, b); }),
  ]);
  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) => GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isActive ? Provider.of<BrowserProvider>(context).neonColor : Colors.white10, shape: BoxShape.circle), child: Icon(icon, size: 18, color: isActive ? Colors.black : Colors.white)), const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70))]));
  void _showSettingsModal(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, setState) { return Container(height: MediaQuery.of(context).size.height * 0.8, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 20)), const SizedBox(height: 20), Expanded(child: ListView(children: [_sectionHeader("Data", b), ListTile(title: const Text("Backup Data", style: TextStyle(color: Colors.white)), onTap: () => b.exportData(context)), ListTile(title: const Text("Restore Data", style: TextStyle(color: Colors.white)), onTap: () { _showImportDialog(context, b); }), ListTile(title: const Text("Factory Reset", style: TextStyle(color: Colors.red)), onTap: () => b.factoryReset()), _sectionHeader("Theme", b), Wrap(spacing: 10, children: [_colorDot(b, const Color(0xFF00FFC2)), _colorDot(b, const Color(0xFFFF0055)), _colorDot(b, const Color(0xFFFFD700))]), _sectionHeader("Security", b), SwitchListTile(activeColor: b.neonColor, title: const Text("Biometric Lock", style: TextStyle(color: Colors.white)), value: b.isBiometricEnabled, onChanged: (v) { b.toggleBiometric(); setState((){}); }), SwitchListTile(activeColor: b.neonColor, title: const Text("AdBlocker", style: TextStyle(color: Colors.white)), value: b.isAdBlockEnabled, onChanged: (v) { b.toggleAdBlock(); setState((){}); })]))])); })); }
  void _showImportDialog(BuildContext context, BrowserProvider b) { final ctrl = TextEditingController(); showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF222222), title: const Text("Import JSON", style: TextStyle(color: Colors.white)), content: TextField(controller: ctrl, maxLines: 5, style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () { if(ctrl.text.isNotEmpty) b.importData(context, ctrl.text); Navigator.pop(context); }, child: const Text("Import"))])); }
  void _showBookmarks(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => Container(height: 500, padding: const EdgeInsets.all(16), child: Column(children: [const Text("Bookmarks", style: TextStyle(color: Colors.white)), Expanded(child: ListView.builder(itemCount: b.bookmarks.length, itemBuilder: (_, i) => ListTile(title: Text(b.bookmarks[i].title, style: const TextStyle(color: Colors.white)), subtitle: Text(b.bookmarks[i].url, style: const TextStyle(color: Colors.grey)), onTap: () { b.loadUrl(b.bookmarks[i].url); Navigator.pop(context); }))) ]))); }
  void _showScriptManager(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => StatefulBuilder(builder: (ctx, setState) => Container(height: 500, padding: const EdgeInsets.all(16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Scripts", style: TextStyle(color: Colors.white)), IconButton(icon: const Icon(Icons.add, color: Colors.green), onPressed: () => _showAddScriptDialog(context, b, setState))]), Expanded(child: ListView.builder(itemCount: b.userScripts.length, itemBuilder: (ctx, i) => ListTile(title: Text(b.userScripts[i].name, style: const TextStyle(color: Colors.white)), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { b.deleteUserScript(b.userScripts[i].id); setState((){}); }))))])))); }
  void _showAddScriptDialog(BuildContext context, BrowserProvider b, StateSetter setState) { final n = TextEditingController(), c = TextEditingController(); showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF222222), title: const Text("New Script"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, style: const TextStyle(color: Colors.white)), TextField(controller: c, style: const TextStyle(color: Colors.white))]), actions: [TextButton(onPressed: () { b.addUserScript(n.text, c.text); setState((){}); Navigator.pop(context); }, child: const Text("Save"))])); }
  void _showDownloads(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => Container(height: 400, padding: const EdgeInsets.all(16), child: Column(children: [const Text("Downloads", style: TextStyle(color: Colors.white)), Expanded(child: ListView.builder(itemCount: b.downloads.length, itemBuilder: (ctx, i) => ListTile(title: Text(b.downloads[i], style: const TextStyle(color: Colors.white))))) ]))); }
  void _showSearch(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b)); }
  void _showDevConsole(BuildContext context) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => const DevConsoleSheet()); }
  Widget _colorDot(BrowserProvider b, Color color) => GestureDetector(onTap: () => b.changeTheme(color), child: Container(width: 30, height: 30, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: b.neonColor == color ? Border.all(color: Colors.white, width: 2) : null)));
  Widget _sectionHeader(String title, BrowserProvider b) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: TextStyle(color: b.neonColor, fontSize: 12, fontWeight: FontWeight.bold)));
}

class StartPage extends StatelessWidget { final BrowserProvider browser; const StartPage({super.key, required this.browser}); @override Widget build(BuildContext context) { return Container(color: Colors.black, child: Center(child: SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Iconsax.global, size: 80, color: browser.neonColor), const SizedBox(height: 40), Container(margin: const EdgeInsets.symmetric(horizontal: 40), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30)), child: TextField(style: const TextStyle(color: Colors.white), textAlign: TextAlign.center, decoration: const InputDecoration(hintText: "Search...", border: InputBorder.none, contentPadding: EdgeInsets.all(16)), onSubmitted: (v) => browser.loadUrl(v))), const SizedBox(height: 40), Wrap(spacing: 20, runSpacing: 20, children: browser.speedDials.map((e) => GestureDetector(onTap: () => browser.loadUrl(e.url), child: Column(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: Icon(Icons.link, color: Color(e.colorValue))), Text(e.label, style: const TextStyle(color: Colors.white54, fontSize: 12))]))).toList())])))); } }
class TabGridPage extends StatelessWidget { final BrowserProvider browser; const TabGridPage({super.key, required this.browser}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Tabs"), actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => browser._addNewTab()), IconButton(icon: const Icon(Icons.close), onPressed: () => browser.toggleTabGrid())]), body: GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16), itemCount: browser.tabs.length, itemBuilder: (context, index) => GestureDetector(onTap: () => browser.switchTab(index), child: Container(decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: index == browser.currentTabIndex ? browser.neonColor : Colors.white10)), child: Column(children: [Expanded(child: browser.tabs[index].thumbnail != null ? Image.memory(browser.tabs[index].thumbnail!, fit: BoxFit.cover) : const Icon(Icons.web)), Text(browser.tabs[index].title, style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 1)]))))); } }
class AiSidebar extends StatelessWidget { const AiSidebar({super.key}); @override Widget build(BuildContext context) { final ai = Provider.of<AiAgentProvider>(context); final browser = Provider.of<BrowserProvider>(context, listen: false); final ctrl = TextEditingController(); return Column(children: [AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => browser.toggleAiSidebar()), title: Text("Co-Pilot", style: TextStyle(color: browser.neonColor)), actions: [IconButton(icon: const Icon(Icons.copy), onPressed: () async { final c = await Clipboard.getData(Clipboard.kTextPlain); if(c != null && c.text != null) { ai.sendMessage(c.text!, browser); }})]), Expanded(child: ListView.builder(itemCount: ai.messages.length, itemBuilder: (ctx, i) => ListTile(title: Text(ai.messages[i].text)))), Padding(padding: const EdgeInsets.all(16), child: TextField(controller: ctrl, onSubmitted: (v) { ai.sendMessage(v, browser); ctrl.clear(); }))]); } }
class GlassBox extends StatelessWidget { final Widget child; final double borderRadius; final EdgeInsets padding; const GlassBox({super.key, required this.child, this.borderRadius = 20, this.padding = const EdgeInsets.all(0)}); @override Widget build(BuildContext context) { return ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(padding: padding, decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.85), borderRadius: BorderRadius.circular(borderRadius), border: Border.all(color: Colors.white.withOpacity(0.1))), child: child))); } }
class SearchSheet extends StatelessWidget { final BrowserProvider browser; const SearchSheet({super.key, required this.browser}); @override Widget build(BuildContext context) { return Container(height: MediaQuery.of(context).size.height * 0.9, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [TextField(controller: browser.urlController, autofocus: true, style: const TextStyle(fontSize: 16, color: Colors.white), decoration: const InputDecoration(hintText: "Search..."), onSubmitted: (v) { browser.loadUrl(v); Navigator.pop(context); })])); } }
class DevConsoleSheet extends StatelessWidget { const DevConsoleSheet({super.key}); @override Widget build(BuildContext context) { final logs = Provider.of<DevToolsProvider>(context).consoleLogs; return Container(height: 400, padding: const EdgeInsets.all(16), child: ListView.builder(itemCount: logs.length, itemBuilder: (ctx, i) => Text(logs[i], style: const TextStyle(color: Colors.green, fontSize: 10)))); } }
class SourceViewerPage extends StatelessWidget { final String html; const SourceViewerPage({super.key, required this.html}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, body: SingleChildScrollView(child: SelectableText(html, style: const TextStyle(color: Colors.white, fontSize: 10)))); } }
class ScannerPage extends StatelessWidget { const ScannerPage({super.key}); @override Widget build(BuildContext context) { return Scaffold(body: MobileScanner(onDetect: (c) { if (c.barcodes.isNotEmpty) { Provider.of<BrowserProvider>(context, listen: false).loadUrl(c.barcodes.first.rawValue!); Navigator.pop(context); } })); } }
class LockScreen extends StatelessWidget { const LockScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(backgroundColor: Colors.black, body: Center(child: Icon(Icons.lock))); }
class _Handler extends WidgetsBindingObserver { final BuildContext ctx; _Handler(this.ctx); @override void didChangeAppLifecycleState(state) { if(state == AppLifecycleState.paused) Provider.of<BrowserProvider>(ctx, listen: false).isLocked = true; else if(state == AppLifecycleState.resumed) Provider.of<BrowserProvider>(ctx, listen: false).checkBiometricLock(ctx); } }
