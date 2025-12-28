import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => AiAgentProvider()),
      ],
      child: const AiBrowserApp(),
    ),
  );
}

class AiBrowserApp extends StatelessWidget {
  const AiBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon AI Browser Real',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFC2),
          secondary: Color(0xFFD500F9),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- LOGIC CORE ---

class HistoryItem {
  final String url;
  final String title;
  final DateTime date;
  HistoryItem({required this.url, required this.title, required this.date});
  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'date': date.toIso8601String()};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    url: json['url'], title: json['title'], date: DateTime.parse(json['date']));
}

class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;
  BrowserTab({required this.id, this.url = "https://www.google.com", this.title = "New Tab", this.isIncognito = false});
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  List<HistoryItem> history = [];
  
  // Settings
  String searchEngine = "https://www.google.com/search?q=";
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true;
  bool isZenMode = false;
  
  // State
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool isMenuOpen = false;
  TextEditingController urlController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  BrowserProvider() {
    _loadData();
    _addNewTab();
  }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      cacheEnabled: !currentTab.isIncognito,
      domStorageEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      userAgent: isDesktopMode
          ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
          : ""
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    final historyList = prefs.getStringList('history') ?? [];
    history = historyList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('searchEngine', searchEngine);
    prefs.setBool('adBlock', isAdBlockEnabled);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _addNewTab([String url = "https://www.google.com", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
    _updateCurrentTabState();
    notifyListeners();
  }

  void switchTab(int index) {
    currentTabIndex = index;
    _updateCurrentTabState();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
      _updateCurrentTabState();
      notifyListeners();
    }
  }

  void _updateCurrentTabState() {
    urlController.text = currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    isLoading = false;
    progress = 0;
  }

  void setController(InAppWebViewController controller) {
    currentTab.controller = controller;
  }

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  Future<void> addToHistory(String url, String? title) async {
    if (currentTab.isIncognito || url == "about:blank" || url.isEmpty) return;
    if (history.isNotEmpty && history.first.url == url) return;

    history.insert(0, HistoryItem(url: url, title: title ?? "Unknown", date: DateTime.now()));
    if (history.length > 100) history.removeLast();
    _saveData();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      if (url.contains(".") && !url.contains(" ")) {
        url = "https://$url";
      } else {
        url = "$searchEngine$url";
      }
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    isMenuOpen = false;
    notifyListeners();
  }

  void toggleMenu() {
    isMenuOpen = !isMenuOpen;
    notifyListeners();
  }
  
  void toggleZenMode() {
    isZenMode = !isZenMode;
    notifyListeners();
  }

  void toggleDesktopMode() async {
    isDesktopMode = !isDesktopMode;
    await currentTab.controller?.setSettings(settings: getSettings());
    reload();
    notifyListeners();
  }

  void toggleAdBlock() async {
    isAdBlockEnabled = !isAdBlockEnabled;
    await _saveData();
    reload();
    notifyListeners();
  }

  void setSearchEngine(String url) {
    searchEngine = url;
    _saveData();
    notifyListeners();
  }

  void clearData() async {
    await currentTab.controller?.clearCache();
    await InAppWebViewController.clearAllCookies();
    history.clear();
    await _saveData();
    notifyListeners();
  }

  Future<void> shareScreenshot(BuildContext context) async {
    try {
      final image = await currentTab.controller?.takeScreenshot();
      if (image == null) throw Exception("Capture failed");
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/snap_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(image);
      await Share.shareXFiles([XFile(file.path)], text: 'Snap from Neon Browser');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void injectScripts(InAppWebViewController controller) {
    if (isAdBlockEnabled) {
      String js = """
        (function() {
          var css = '.ad, .ads, .advertisement, [id^="google_ads"], iframe[src*="ads"], div[class*="sponsored"] { display: none !important; visibility: hidden !important; height: 0 !important; }';
          var style = document.createElement('style');
          style.type = 'text/css';
          style.appendChild(document.createTextNode(css));
          document.head.appendChild(style);
        })();
      """;
      controller.evaluateJavascript(source: js);
    }
  }

  void startVoiceSearch(BuildContext context) async {
    var status = await Permission.microphone.request();
    if (status.isGranted && await _speech.initialize()) {
      _isListening = true;
      notifyListeners();
      _speech.listen(onResult: (result) {
        if (result.finalResult) {
          _isListening = false;
          loadUrl(result.recognizedWords);
          notifyListeners();
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mic Permission Denied")));
    }
  }

  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Browser Command Interface Online.\nTry 'Go to Google' or 'Switch to Desktop'.", isUser: false)];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider browser) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();
    await Future.delayed(const Duration(seconds: 1));
    
    String response = "Command processed.";
    String lower = text.toLowerCase();
    
    // REAL COMMAND PARSING
    if (lower.contains("google")) {
      browser.loadUrl("https://google.com");
      response = "Navigating to Google.";
    } else if (lower.contains("youtube")) {
      browser.loadUrl("https://youtube.com");
      response = "Opening YouTube.";
    } else if (lower.contains("desktop")) {
      browser.toggleDesktopMode();
      response = "Desktop Mode ${browser.isDesktopMode ? "Activated" : "Deactivated"}.";
    } else if (lower.contains("adblock")) {
      browser.toggleAdBlock();
      response = "AdBlock ${browser.isAdBlockEnabled ? "Active" : "Disabled"}.";
    } else if (lower.contains("clear") || lower.contains("delete")) {
      browser.clearData();
      response = "Browsing data wiped.";
    } else if (lower.contains("incognito") || lower.contains("private")) {
      browser._addNewTab("https://google.com", true);
      response = "New Private Tab opened.";
    } else {
      response = "I can browse, change settings, or secure data. Be specific.";
    }
    
    messages.add(ChatMessage(text: response, isUser: false));
    isThinking = false;
    notifyListeners();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

// --- UI COMPONENTS ---

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color color;
  final BorderRadius? borderRadius;

  const GlassContainer({super.key, required this.child, this.blur = 10, this.opacity = 0.2, this.color = Colors.black, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(opacity),
            borderRadius: borderRadius ?? BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});
  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InAppWebView(
              key: ValueKey(browser.currentTab.id),
              initialUrlRequest: URLRequest(url: WebUri(browser.currentTab.url)),
              initialSettings: browser.getSettings(),
              onWebViewCreated: (c) => browser.setController(c),
              onLoadStart: (c, url) => browser.updateUrl(url.toString()),
              onLoadStop: (c, url) async {
                browser.progress = 1.0;
                browser.updateUrl(url.toString());
                browser.injectScripts(c);
                browser.addToHistory(url.toString(), await c.getTitle());
              },
              onProgressChanged: (c, p) => browser.progress = p / 100,
            ),
          ),
          if (browser.progress < 1.0)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(value: browser.progress, minHeight: 3, color: Theme.of(context).colorScheme.primary, backgroundColor: Colors.transparent),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: browser.isZenMode ? -150 : 30,
            left: 20, right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: browser.isMenuOpen 
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassContainer(
                          blur: 15, opacity: 0.8, color: const Color(0xFF121212),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(children: [_buildGridMenu(context, browser), const SizedBox(height: 12), _buildTabStrip(browser)]),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                ),
                GlassContainer(
                  blur: 20, opacity: 0.6, color: Colors.black, borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(icon: Icon(browser.isMenuOpen ? Icons.close : Iconsax.category, color: Colors.white), onPressed: browser.toggleMenu),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showSearchModal(context, browser),
                            child: Container(
                              height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  if (browser.currentTab.isIncognito) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Iconsax.mask, size: 14, color: Colors.purpleAccent)),
                                  Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.greenAccent : Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(browser.currentTab.url.replaceFirst("https://", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => const AiAgentPanel()),
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) => Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.5 * _pulseController.value), blurRadius: 10 + (10 * _pulseController.value))]
                              ),
                              child: const Icon(Iconsax.magic_star, color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (browser.isZenMode)
            Positioned(
              bottom: 20, right: 20,
              child: FloatingActionButton.small(backgroundColor: Colors.white.withOpacity(0.2), elevation: 0, child: const Icon(Icons.expand_less, color: Colors.white), onPressed: browser.toggleZenMode),
            ),
        ],
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context, BrowserProvider browser) {
    // Definisi tombol menu dengan feedback langsung
    final items = [
      {'icon': Iconsax.arrow_left_2, 'label': 'Back', 'action': () { browser.goBack(); }},
      {'icon': Iconsax.arrow_right_3, 'label': 'Forward', 'action': () { browser.goForward(); }},
      {'icon': Iconsax.refresh, 'label': 'Reload', 'action': () { browser.reload(); }},
      {'icon': Iconsax.add, 'label': 'New Tab', 'action': () { browser._addNewTab(); browser.toggleMenu(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New Tab Opened"), duration: Duration(milliseconds: 500))); }},
      {'icon': Iconsax.mask, 'label': 'Incognito', 'action': () { browser._addNewTab("https://google.com", true); browser.toggleMenu(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incognito Mode"), duration: Duration(milliseconds: 500))); }},
      {'icon': Iconsax.monitor, 'label': 'Desktop', 'action': () { browser.toggleDesktopMode(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Desktop Mode ${browser.isDesktopMode ? "ON" : "OFF"}"), duration: const Duration(milliseconds: 500))); }},
      {'icon': Iconsax.camera, 'label': 'Snap', 'action': () { browser.shareScreenshot(context); browser.toggleMenu(); }},
      {'icon': Iconsax.clock, 'label': 'History', 'action': () { _showHistoryModal(context, browser); }},
      {'icon': Iconsax.eye_slash, 'label': 'Zen Mode', 'action': () { browser.toggleZenMode(); browser.toggleMenu(); }},
      {'icon': Iconsax.setting, 'label': 'Settings', 'action': () { _showSettingsModal(context, browser); }},
    ];

    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 16, crossAxisSpacing: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        bool isActive = false;
        if (item['label'] == 'Desktop') isActive = browser.isDesktopMode;

        return InkWell(
          onTap: item['action'] as VoidCallback,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: isActive ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(item['icon'] as IconData, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 4),
              Text(item['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 9), textAlign: TextAlign.center),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabStrip(BrowserProvider browser) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: browser.tabs.length,
        separatorBuilder: (_,__) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = browser.tabs[index];
          final isActive = index == browser.currentTabIndex;
          return GestureDetector(
            onTap: () => browser.switchTab(index),
            child: Container(
              width: 100, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)) : null,
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  if (tab.isIncognito) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Iconsax.mask, size: 10, color: Colors.purpleAccent)),
                  Expanded(child: Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: () => browser.closeTab(index), child: const Icon(Icons.close, size: 12, color: Colors.white30))
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHistoryModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => SizedBox(height: 400, child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text("History", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
      Expanded(child: ListView.builder(itemCount: browser.history.length, itemBuilder: (_, i) {
        final item = browser.history[i];
        return ListTile(title: Text(item.title, style: const TextStyle(color: Colors.white), maxLines: 1), subtitle: Text(item.url, style: const TextStyle(color: Colors.grey), maxLines: 1), onTap: () { browser.loadUrl(item.url); Navigator.pop(context); browser.isMenuOpen = false; });
      })),
      TextButton(onPressed: () { browser.clearData(); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("History Cleared"))); }, child: const Text("Clear All Data", style: TextStyle(color: Colors.red)))
    ])));
  }

  void _showSettingsModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => StatefulBuilder(builder: (ctx, setState) => SizedBox(height: 350, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const Divider(color: Colors.white24),
      SwitchListTile(title: const Text("AdBlock", style: TextStyle(color: Colors.white)), value: browser.isAdBlockEnabled, onChanged: (v) { browser.toggleAdBlock(); setState((){}); }),
      ListTile(title: const Text("Search Engine", style: TextStyle(color: Colors.white)), subtitle: Text(browser.searchEngine.contains("google") ? "Google" : "DuckDuckGo", style: const TextStyle(color: Colors.grey)), onTap: () {
        browser.setSearchEngine(browser.searchEngine.contains("google") ? "https://duckduckgo.com/?q=" : "https://www.google.com/search?q=");
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Engine: ${browser.searchEngine.contains("google") ? "Google" : "DuckDuckGo"}")));
      }),
    ]))));
  }

  void _showSearchModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: browser.urlController, autofocus: true, style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search or type URL", hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Iconsax.search_normal, color: Colors.white54),
                  filled: true, fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  suffixIcon: IconButton(icon: const Icon(Iconsax.microphone), onPressed: () { browser.startVoiceSearch(context); Navigator.pop(context); }),
                ),
                onSubmitted: (value) { browser.loadUrl(value); Navigator.pop(context); },
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _quickChip(browser, "Google", "google.com", Icons.search, context),
                _quickChip(browser, "YouTube", "youtube.com", Iconsax.video, context),
                _quickChip(browser, "News", "cnn.com", Iconsax.global, context),
                _quickChip(browser, "ChatGPT", "chat.openai.com", Iconsax.message, context),
              ])
            ],
          ),
        );
      },
    );
  }

  Widget _quickChip(BrowserProvider b, String label, String url, IconData icon, BuildContext ctx) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Colors.white),
      label: Text(label), backgroundColor: Colors.white.withOpacity(0.1),
      labelStyle: const TextStyle(color: Colors.white), side: BorderSide.none,
      onPressed: () { b.loadUrl(url); Navigator.pop(ctx); },
    );
  }
}

class AiAgentPanel extends StatelessWidget {
  const AiAgentPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final aiProvider = Provider.of<AiAgentProvider>(context, listen: false);
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    final textController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
         const SizedBox(height: 10),
         Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
         const SizedBox(height: 10),
         const Icon(Iconsax.magic_star, size: 40, color: Color(0xFF00FFC2)),
         const Text("Neon Core AI", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
         const Divider(color: Colors.white12),
         Expanded(child: ListView.builder(
           padding: const EdgeInsets.all(16),
           itemCount: aiProvider.messages.length,
           itemBuilder: (ctx, i) {
             final msg = aiProvider.messages[i];
             return Align(alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: msg.isUser ? const Color(0xFF00FFC2).withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(12)), child: Text(msg.text, style: const TextStyle(color: Colors.white))));
           }
         )),
         if (aiProvider.isThinking) const LinearProgressIndicator(minHeight: 2, color: Color(0xFF00FFC2)),
         Padding(padding: const EdgeInsets.all(16), child: TextField(
           controller: textController,
           style: const TextStyle(color: Colors.white),
           decoration: InputDecoration(
             hintText: "Command me (e.g. 'Open Youtube')",
             hintStyle: const TextStyle(color: Colors.white30),
             filled: true, fillColor: Colors.black26,
             border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
             suffixIcon: IconButton(icon: const Icon(Icons.send, color: Color(0xFF00FFC2)), onPressed: () {
               if (textController.text.isNotEmpty) {
                 aiProvider.sendMessage(textController.text, browser);
                 textController.clear();
               }
             }),
           ),
           onSubmitted: (v) {
             if (v.isNotEmpty) { aiProvider.sendMessage(v, browser); textController.clear(); }
           },
         )),
         SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ]),
    );
  }
}