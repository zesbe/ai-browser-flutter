import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

void main() {
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
  InAppWebViewController? controller;
  Uint8List? screenshot; // For tab switcher thumbnail

  BrowserTab({required this.id, this.url = "https://www.google.com", this.title = "New Tab"});
}

// --- Providers ---

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  
  // State for current tab
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true; // Default ON
  bool isReaderMode = false;
  
  TextEditingController urlController = TextEditingController();
  
  // Voice
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  BrowserProvider() {
    _addNewTab();
  }

  BrowserTab get currentTab => tabs[currentTabIndex];

  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    cacheEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    useWideViewPort: true,
    safeBrowsingEnabled: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
  );

  // --- Tab Management ---
  void _addNewTab([String url = "https://www.google.com"]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url);
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
      // Don't close the last tab, just reset it
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
    // Reset transient states
    progress = 0;
    isLoading = false;
  }

  // --- WebView Actions ---
  
  void setController(InAppWebViewController controller) {
    currentTab.controller = controller;
    
    // Inject AdBlock if enabled
    if (isAdBlockEnabled) {
      _injectAdBlocker(controller);
    }
  }

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void updateTitle(String? title) {
    if (title != null) {
      currentTab.title = title;
      notifyListeners();
    }
  }

  void updateProgress(double p) {
    progress = p;
    isLoading = p < 1.0;
    notifyListeners();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      if (url.contains(".") && !url.contains(" ")) {
        url = "https://$url";
      } else {
        url = "https://www.google.com/search?q=$url";
      }
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void toggleDesktopMode() async {
    isDesktopMode = !isDesktopMode;
    settings.preferredContentMode = isDesktopMode 
        ? UserPreferredContentMode.DESKTOP 
        : UserPreferredContentMode.MOBILE;
    settings.userAgent = isDesktopMode
        ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        : ""; 
        
    await currentTab.controller?.setSettings(settings: settings);
    reload();
    notifyListeners();
  }

  // --- Features ---

  void toggleReaderMode() {
    isReaderMode = !isReaderMode;
    if (isReaderMode) {
      // Simple Readability logic (removes non-article content)
      String js = """
        var readability = document.createElement('script');
        readability.src = 'https://unpkg.com/@mozilla/readability/Readability.js';
        document.head.appendChild(readability);
        
        // Wait for script, then execute (simplified for demo)
        // Actual implementation requires offline Readability.js source code or parsing
        // For this demo, we'll use a CSS filter approach
        
        var style = document.createElement('style');
        style.id = 'reader-mode-css';
        style.innerHTML = `
          body { font-family: sans-serif !important; line-height: 1.6 !important; max-width: 800px !important; margin: 0 auto !important; background: #fdf6e3 !important; color: #111 !important; padding: 20px !important; }
          nav, footer, aside, .ad, .ads, .social-share, #comments { display: none !important; }
        `;
        document.head.appendChild(style);
      """;
      currentTab.controller?.evaluateJavascript(source: js);
    } else {
      // Remove reader styles logic would go here (usually easier to reload)
      reload();
    }
    notifyListeners();
  }

  void _injectAdBlocker(InAppWebViewController controller) {
    // Basic CSS hider for common ad classes
    String css = """
      .ad, .ads, .advertisement, .banner-ad, [id^="google_ads"], [class^="ad-"], [class*=" ad "], iframe[src*="ads"] {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        width: 0 !important;
      }
    """;
    controller.injectCSSCode(source: css);
  }

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

  void goBack() async {
    if (await currentTab.controller?.canGoBack() ?? false) {
      currentTab.controller?.goBack();
    }
  }

  void goForward() async {
    if (await currentTab.controller?.canGoForward() ?? false) {
      currentTab.controller?.goForward();
    }
  }

  void reload() {
    currentTab.controller?.reload();
  }
}

class AiAgentProvider extends ChangeNotifier {
  // (Same AI implementation as before)
  List<ChatMessage> messages = [
    ChatMessage(text: "Ultimate Agent ready. I can control the browser (e.g., 'Turn on reader mode').", isUser: false),
  ];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider browser) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    
    String response = "I understand.";
    String lower = text.toLowerCase();
    
    if (lower.contains("reader")) {
      browser.toggleReaderMode();
      response = "I've toggled Reader Mode for you.";
    } else if (lower.contains("desktop")) {
      browser.toggleDesktopMode();
      response = "Switched to Desktop Mode.";
    } else if (lower.contains("summarize")) {
      response = "Page Summary:\nThis page discusses key concepts about..."; 
    } else {
       response = "I can help you navigate or analyze this page. Try asking for a summary or to change modes.";
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

    // If showing tab switcher (future implementation), conditionally return that widget
    // For now, we show the current tab view

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Ultimate Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Secure Icon
                      Icon(
                        browserProvider.isSecure ? Iconsax.lock5 : Iconsax.unlock,
                        size: 16,
                        color: browserProvider.isSecure ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      
                      // URL Bar
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
                              suffixIcon: IconButton(
                                icon: Icon(browserProvider._isListening ? Icons.mic : Iconsax.microphone),
                                color: browserProvider._isListening ? Colors.red : null,
                                onPressed: () => browserProvider.startVoiceSearch(context),
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (value) => browserProvider.loadUrl(value),
                          ),
                        ),
                      ),
                      
                      // Tab Count Button
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
                          child: Text(
                            "${browserProvider.tabs.length}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (browserProvider.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: LinearProgressIndicator(
                        value: browserProvider.progress, 
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
            
            // WebView Stack (IndexedStack for preserving state is complex with WebViews, 
            // simpler to rebuild for this MVP or use Offstage if memory permits. 
            // For MVP, we just render current Tab)
            Expanded(
              child: InAppWebView(
                key: ValueKey(browserProvider.currentTab.id), // Unique key forces rebuild on tab switch if needed
                initialUrlRequest: URLRequest(url: WebUri(browserProvider.currentTab.url)),
                initialSettings: browserProvider.settings,
                onWebViewCreated: (controller) {
                  browserProvider.setController(controller);
                },
                onLoadStart: (controller, url) {
                  browserProvider.updateUrl(url.toString());
                },
                onLoadStop: (controller, url) async {
                  browserProvider.updateProgress(1.0);
                  browserProvider.updateUrl(url.toString());
                  browserProvider.updateTitle(await controller.getTitle());
                },
                onProgressChanged: (controller, progress) {
                  browserProvider.updateProgress(progress / 100);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).colorScheme.surface,
        elevation: 12,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Iconsax.arrow_left_2), onPressed: browserProvider.goBack),
            IconButton(icon: const Icon(Iconsax.arrow_right_3), onPressed: browserProvider.goForward),
            
            // AI Action Button (Central)
            FloatingActionButton(
              elevation: 2,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Iconsax.magic_star),
              onPressed: () {
                 showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const AiAgentPanel(),
                );
              },
            ),
            
            IconButton(icon: const Icon(Iconsax.book_1), 
              color: browserProvider.isReaderMode ? Colors.green : null,
              onPressed: browserProvider.toggleReaderMode
            ),
            IconButton(icon: const Icon(Iconsax.category), onPressed: () => _showToolsMenu(context, browserProvider)),
          ],
        ),
      ),
    );
  }

  void _showTabSwitcher(BuildContext context, BrowserProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              AppBar(
                title: const Text("Tabs"),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(icon: const Icon(Icons.add), onPressed: () {
                    provider._addNewTab();
                    Navigator.pop(context);
                  }),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tab = provider.tabs[index];
                    final isSelected = index == provider.currentTabIndex;
                    return ListTile(
                      tileColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(tab.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(tab.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      leading: const Icon(Iconsax.global),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          provider.closeTab(index);
                          // Rebuild handled by provider listener
                          Navigator.pop(context); 
                          _showTabSwitcher(context, provider); // Re-open to refresh
                        },
                      ),
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

  void _showToolsMenu(BuildContext context, BrowserProvider provider) {
    // (Same Tools menu as before, but added Reader Mode toggle already in BottomBar)
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 350,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Tools", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  children: [
                    _ToolIcon(
                      icon: provider.isDesktopMode ? Icons.monitor : Icons.smartphone, 
                      label: provider.isDesktopMode ? "Mobile" : "Desktop",
                      isActive: provider.isDesktopMode,
                      onTap: () {
                        provider.toggleDesktopMode();
                        Navigator.pop(context);
                      },
                    ),
                    _ToolIcon(
                      icon: Icons.block, 
                      label: "AdBlock",
                      isActive: provider.isAdBlockEnabled,
                      onTap: () {
                        provider.isAdBlockEnabled = !provider.isAdBlockEnabled;
                        provider.reload();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("AdBlock ${provider.isAdBlockEnabled ? "ON" : "OFF"}")));
                      },
                    ),
                    _ToolIcon(
                      icon: Iconsax.share, label: "Share",
                      onTap: () { Share.share(provider.currentTab.url); Navigator.pop(context); }
                    ),
                    _ToolIcon(icon: Iconsax.printer, label: "Print", onTap: () => Navigator.pop(context)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ToolIcon({required this.icon, required this.label, required this.onTap, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
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
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Iconsax.magic_star, size: 32, color: Colors.blueAccent),
          const Text("Browser Copilot", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
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
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(msg.text, style: TextStyle(color: msg.isUser ? Colors.white : Colors.black87)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: textController,
              decoration: InputDecoration(
                hintText: "Ask AI...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () {
                  if (textController.text.isNotEmpty) {
                    aiProvider.sendMessage(textController.text, browserProvider);
                    textController.clear();
                  }
                }),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                   aiProvider.sendMessage(value, browserProvider);
                   textController.clear();
                }
              },
            ),
          )
        ],
      ),
    );
  }
}
