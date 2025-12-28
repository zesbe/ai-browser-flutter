import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
      title: 'Ultimate AI Browser',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052CC),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8DA4F7),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Models ---
class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;

  BrowserTab({
    required this.id, 
    this.url = "https://www.google.com", 
    this.title = "New Tab",
    this.isIncognito = false,
  });
}

class HistoryItem {
  final String url;
  final String title;
  final DateTime date;

  HistoryItem({required this.url, required this.title, required this.date});

  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'date': date.toIso8601String()};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    url: json['url'], title: json['title'], date: DateTime.parse(json['date']));
}

class BookmarkItem {
  final String url;
  final String title;
  BookmarkItem({required this.url, required this.title});
  
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(url: json['url'], title: json['title']);
}

// --- Providers ---

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  
  List<HistoryItem> history = [];
  List<BookmarkItem> bookmarks = [];
  
  // Settings
  String searchEngine = "https://www.google.com/search?q=";
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true;
  bool isReaderMode = false;
  bool isForceDarkWeb = false;
  
  // State
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool showFindOnPage = false;
  TextEditingController urlController = TextEditingController();
  TextEditingController findController = TextEditingController();
  
  // Voice
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
      cacheEnabled: !currentTab.isIncognito, // No cache in incognito
      domStorageEnabled: !currentTab.isIncognito,
      databaseEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      userAgent: isDesktopMode
          ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
          : "" // Default
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load History
    final historyList = prefs.getStringList('history') ?? [];
    history = historyList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    
    // Load Bookmarks
    final bookmarksList = prefs.getStringList('bookmarks') ?? [];
    bookmarks = bookmarksList.map((e) => BookmarkItem.fromJson(jsonDecode(e))).toList();
    
    // Load Settings
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('bookmarks', bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setString('searchEngine', searchEngine);
  }

  // --- Tab Management ---
  void _addNewTab([String url = "https://www.google.com", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
    _updateCurrentTabState();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) {
        currentTabIndex = tabs.length - 1;
      }
      _updateCurrentTabState();
      notifyListeners();
    } else {
      loadUrl("https://www.google.com");
    }
  }

  void switchTab(int index) {
    currentTabIndex = index;
    _updateCurrentTabState();
    notifyListeners();
  }

  void _updateCurrentTabState() {
    urlController.text = currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    progress = 0;
    isLoading = false;
    showFindOnPage = false;
  }

  // --- Core Browser Logic ---

  void setController(InAppWebViewController controller) {
    currentTab.controller = controller;
    if (isAdBlockEnabled) _injectAdBlocker(controller);
    if (isForceDarkWeb) _injectDarkMode(controller);
  }

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void addToHistory(String url, String? title) {
    if (currentTab.isIncognito) return;
    if (url.isEmpty || url == "about:blank") return;
    
    // Avoid duplicates on top
    if (history.isNotEmpty && history.first.url == url) return;

    history.insert(0, HistoryItem(url: url, title: title ?? "Unknown", date: DateTime.now()));
    if (history.length > 200) history.removeLast(); // Limit history
    _saveData();
  }

  void toggleBookmark() {
    final url = currentTab.url;
    final exists = bookmarks.any((b) => b.url == url);
    if (exists) {
      bookmarks.removeWhere((b) => b.url == url);
    } else {
      bookmarks.add(BookmarkItem(url: url, title: currentTab.title));
    }
    _saveData();
    notifyListeners();
  }

  bool isBookmarked(String url) {
    return bookmarks.any((b) => b.url == url);
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
  }

  void setSearchEngine(String engineUrl) {
    searchEngine = engineUrl;
    _saveData();
    notifyListeners();
  }

  // --- Features ---

  void toggleForceDark() {
    isForceDarkWeb = !isForceDarkWeb;
    reload(); 
    notifyListeners();
  }
  
  void _injectDarkMode(InAppWebViewController controller) {
     // Powerful filter based dark mode
     String js = """
      var style = document.createElement('style');
      style.innerHTML = `
        html { filter: invert(1) hue-rotate(180deg) !important; }
        img, video, iframe, canvas { filter: invert(1) hue-rotate(180deg) !important; }
      `;
      document.head.appendChild(style);
     """;
     controller.evaluateJavascript(source: js);
  }

  void _injectAdBlocker(InAppWebViewController controller) {
    String css = """
      .ad, .ads, .advertisement, [id^="google_ads"], [class^="ad-"], iframe[src*="ads"] { display: none !important; }
    """;
    controller.injectCSSCode(source: css);
  }

  void findInPage(String query) {
    if (query.isEmpty) {
      currentTab.controller?.clearMatches();
    } else {
      currentTab.controller?.findAllAsync(find: query);
    }
  }

  void toggleFindOnPage() {
    showFindOnPage = !showFindOnPage;
    if (!showFindOnPage) currentTab.controller?.clearMatches();
    notifyListeners();
  }

  // --- Voice & Utils ---
  void startVoiceSearch(BuildContext context) async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      bool available = await _speech.initialize();
      if (available) {
        _isListening = true;
        notifyListeners();
        _speech.listen(onResult: (result) {
          if (result.finalResult) {
            _isListening = false;
            loadUrl(result.recognizedWords);
            notifyListeners();
          }
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Microphone permission needed")));
    }
  }

  void reload() => currentTab.controller?.reload();
  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [
    ChatMessage(text: "Browser OS ready. I can manage tabs, bookmarks, and settings.", isUser: false),
  ];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider browser) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    String lower = text.toLowerCase();
    String response = "Action completed.";

    if (lower.contains("incognito")) {
      browser._addNewTab("https://www.google.com", true);
      response = "Opened a new Incognito tab.";
    } else if (lower.contains("history")) {
      response = "You have visited ${browser.history.length} pages recently.";
    } else if (lower.contains("dark")) {
      browser.toggleForceDark();
      response = "Toggled Dark Web Mode.";
    } else {
      response = "I can open Incognito tabs, check history, or toggle dark mode for you.";
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

// --- UI ---

class BrowserHomePage extends StatelessWidget {
  const BrowserHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final browserProvider = Provider.of<BrowserProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: browserProvider.currentTab.isIncognito ? Colors.grey[900] : Theme.of(context).colorScheme.surface,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (browserProvider.currentTab.isIncognito)
                         const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Iconsax.mask, color: Colors.white)),
                      
                      Icon(
                        browserProvider.isSecure ? Iconsax.lock5 : Iconsax.unlock,
                        size: 16,
                        color: browserProvider.isSecure ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: browserProvider.urlController,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              hintText: "Search or enter URL",
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(browserProvider._isListening ? Icons.mic : Iconsax.microphone),
                                    onPressed: () => browserProvider.startVoiceSearch(context),
                                  ),
                                ],
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (value) => browserProvider.loadUrl(value),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _showTabSwitcher(context, browserProvider),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text("${browserProvider.tabs.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  if (browserProvider.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: LinearProgressIndicator(value: browserProvider.progress, minHeight: 2),
                    ),
                  
                  // FIND IN PAGE BAR
                  if (browserProvider.showFindOnPage)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: browserProvider.findController,
                              decoration: const InputDecoration(hintText: "Find in page..."),
                              onChanged: (val) => browserProvider.findInPage(val),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: browserProvider.toggleFindOnPage)
                        ],
                      ),
                    )
                ],
              ),
            ),
            
            // --- WEBVIEW ---
            Expanded(
              child: InAppWebView(
                key: ValueKey(browserProvider.currentTab.id),
                initialUrlRequest: URLRequest(url: WebUri(browserProvider.currentTab.url)),
                initialSettings: browserProvider.getSettings(),
                onWebViewCreated: (controller) => browserProvider.setController(controller),
                onLoadStart: (controller, url) => browserProvider.updateUrl(url.toString()),
                onLoadStop: (controller, url) async {
                  browserProvider.updateProgress(1.0);
                  final title = await controller.getTitle();
                  browserProvider.currentTab.title = title ?? "No Title";
                  browserProvider.addToHistory(url.toString(), title);
                },
                onProgressChanged: (controller, progress) => browserProvider.updateProgress(progress / 100),
                onDownloadStartRequest: (controller, request) async {
                   final url = Uri.parse(request.url.toString());
                   if (await canLaunchUrl(url)) {
                     await launchUrl(url, mode: LaunchMode.externalApplication);
                   }
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Iconsax.arrow_left_2), onPressed: browserProvider.goBack),
            IconButton(icon: const Icon(Iconsax.arrow_right_3), onPressed: browserProvider.goForward),
            FloatingActionButton(
              elevation: 2,
              mini: true,
              child: const Icon(Iconsax.magic_star),
              onPressed: () => showModalBottomSheet(context: context, builder: (_) => const AiAgentPanel()),
            ),
            IconButton(icon: const Icon(Iconsax.document_download), onPressed: () => _showDownloadsHistory(context, browserProvider)),
            IconButton(icon: const Icon(Iconsax.setting_2), onPressed: () => _showSettings(context, browserProvider)),
          ],
        ),
      ),
    );
  }

  // --- SUB MENUS ---

  void _showTabSwitcher(BuildContext context, BrowserProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              AppBar(
                title: const Text("Tabs"), 
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(icon: const Icon(Iconsax.add), onPressed: () {
                    provider._addNewTab();
                    Navigator.pop(context);
                  }),
                   IconButton(icon: const Icon(Iconsax.mask), onPressed: () {
                    provider._addNewTab("https://www.google.com", true);
                    Navigator.pop(context);
                  }),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.tabs.length,
                  itemBuilder: (context, index) {
                    final tab = provider.tabs[index];
                    return ListTile(
                      title: Text(tab.title),
                      subtitle: Text(tab.url),
                      leading: Icon(tab.isIncognito ? Iconsax.mask : Iconsax.global),
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () {
                        provider.closeTab(index);
                        Navigator.pop(context);
                      }),
                      onTap: () {
                        provider.switchTab(index);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDownloadsHistory(BuildContext context, BrowserProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(tabs: [Tab(text: "History"), Tab(text: "Bookmarks")]),
              Expanded(
                child: TabBarView(
                  children: [
                    // HISTORY
                    ListView.builder(
                      itemCount: provider.history.length,
                      itemBuilder: (_, i) {
                        final item = provider.history[i];
                        return ListTile(
                          title: Text(item.title, maxLines: 1),
                          subtitle: Text(item.url, maxLines: 1),
                          onTap: () { provider.loadUrl(item.url); Navigator.pop(context); },
                        );
                      }
                    ),
                    // BOOKMARKS
                    ListView.builder(
                      itemCount: provider.bookmarks.length,
                      itemBuilder: (_, i) {
                        final item = provider.bookmarks[i];
                        return ListTile(
                          title: Text(item.title),
                          leading: const Icon(Iconsax.star1, color: Colors.orange),
                          onTap: () { provider.loadUrl(item.url); Navigator.pop(context); },
                        );
                      }
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context, BrowserProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text("Tools & Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            ListTile(
              leading: Icon(provider.isBookmarked(provider.currentTab.url) ? Iconsax.star1 : Iconsax.star, 
                color: provider.isBookmarked(provider.currentTab.url) ? Colors.orange : null),
              title: const Text("Bookmark This Page"),
              onTap: () { provider.toggleBookmark(); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Iconsax.search_status),
              title: const Text("Find in Page"),
              onTap: () { provider.toggleFindOnPage(); Navigator.pop(context); },
            ),
            SwitchListTile(
              title: const Text("Dark Web Mode"),
              subtitle: const Text("Force dark theme on all sites"),
              value: provider.isForceDarkWeb,
              onChanged: (val) { provider.toggleForceDark(); Navigator.pop(context); },
            ),
             SwitchListTile(
              title: const Text("Desktop Mode"),
              value: provider.isDesktopMode,
              onChanged: (val) { 
                provider.isDesktopMode = !provider.isDesktopMode; 
                provider.reload();
                Navigator.pop(context); 
              },
            ),
             ListTile(
              leading: const Icon(Icons.search),
              title: const Text("Search Engine"),
              subtitle: Text(provider.searchEngine.contains("google") ? "Google" : "DuckDuckGo"),
              onTap: () {
                provider.setSearchEngine(
                  provider.searchEngine.contains("google") 
                  ? "https://duckduckgo.com/?q=" 
                  : "https://www.google.com/search?q="
                );
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}

class AiAgentPanel extends StatelessWidget {
  const AiAgentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final aiProvider = Provider.of<AiAgentProvider>(context);
    final browserProvider = Provider.of<BrowserProvider>(context, listen: false);
    final textController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text("AI Assistant", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: aiProvider.messages.length,
              itemBuilder: (context, index) {
                final msg = aiProvider.messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isUser ? Colors.blueAccent : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(msg.text, style: TextStyle(color: msg.isUser ? Colors.white : Colors.black)),
                  ),
                );
              },
            ),
          ),
          TextField(
            controller: textController,
            decoration: InputDecoration(
              hintText: "Try 'Open incognito' or 'Dark mode'",
              suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () {
                aiProvider.sendMessage(textController.text, browserProvider);
                textController.clear();
              }),
            ),
            onSubmitted: (v) {
               aiProvider.sendMessage(v, browserProvider);
               textController.clear();
            },
          )
        ],
      ),
    );
  }
}