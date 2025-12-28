import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';

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
      title: 'Enterprise AI Browser',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052CC), // Enterprise Blue
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8DA4F7),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Providers ---

class BrowserProvider extends ChangeNotifier {
  InAppWebViewController? webViewController;
  String currentUrl = "https://www.google.com";
  String pageTitle = "New Tab";
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool isDesktopMode = false;
  
  TextEditingController urlController = TextEditingController(text: "https://www.google.com");

  // Enterprise Settings
  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    cacheEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    useWideViewPort: true,
    safeBrowsingEnabled: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
  );

  void setController(InAppWebViewController controller) {
    webViewController = controller;
  }

  void updateUrl(String url) {
    currentUrl = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void updateTitle(String? title) {
    if (title != null) {
      pageTitle = title;
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
      if (url.contains(".")) {
        url = "https://$url";
      } else {
        url = "https://www.google.com/search?q=$url";
      }
    }
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void toggleDesktopMode() async {
    isDesktopMode = !isDesktopMode;
    settings.preferredContentMode = isDesktopMode 
        ? UserPreferredContentMode.DESKTOP 
        : UserPreferredContentMode.MOBILE;
    settings.userAgent = isDesktopMode
        ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        : ""; // Default
        
    await webViewController?.setSettings(settings: settings);
    reload();
    notifyListeners();
  }

  Future<void> clearBrowsingData() async {
    await webViewController?.clearCache();
    await InAppWebViewController.clearAllCookies();
    // Also clear storage
    await WebStorageManager.instance().deleteAllData();
  }

  void goBack() async {
    if (await webViewController?.canGoBack() ?? false) {
      webViewController?.goBack();
    }
  }

  void goForward() async {
    if (await webViewController?.canGoForward() ?? false) {
      webViewController?.goForward();
    }
  }

  void reload() {
    webViewController?.reload();
  }
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [
    ChatMessage(
      text: "Enterprise Agent ready. I can summarize this page, extract data, or draft emails based on content.",
      isUser: false,
    ),
  ];
  bool isThinking = false;

  void sendMessage(String text, String currentContextUrl) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();

    // Simulate Enterprise AI Logic
    await Future.delayed(const Duration(seconds: 1));
    
    String response = "Processing request...";
    
    if (text.toLowerCase().contains("summarize")) {
      response = "EXECUTIVE SUMMARY for $currentContextUrl:\n\n1. Key Point A regarding the topic.\n2. Key Point B regarding the market data.\n3. Actionable insight derived from the text.";
    } else if (text.toLowerCase().contains("desktop")) {
      response = "I see you are viewing this in Desktop Mode. This is useful for complex dashboards.";
    } else {
      response = "I have analyzed the page content at $currentContextUrl. How would you like me to process this data?";
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
            // Professional Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                ]
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        browserProvider.isSecure ? Iconsax.lock5 : Iconsax.unlock,
                        size: 16,
                        color: browserProvider.isSecure ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: browserProvider.urlController,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              hintText: "Enter secure URL",
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (value) => browserProvider.loadUrl(value),
                          ),
                        ),
                      ),
                      if (browserProvider.isLoading)
                        const SizedBox(width: 40, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                      else
                         IconButton(icon: const Icon(Iconsax.refresh), onPressed: browserProvider.reload),
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
            
            // WebView
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri("https://www.google.com")),
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
                onTitleChanged: (controller, title) {
                  browserProvider.updateTitle(title);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Iconsax.arrow_left_2), onPressed: browserProvider.goBack),
            IconButton(icon: const Icon(Iconsax.arrow_right_3), onPressed: browserProvider.goForward),
            
            // AI Action Button (Central)
            FloatingActionButton.small(
              elevation: 0,
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
            
            IconButton(icon: const Icon(Iconsax.category), onPressed: () => _showToolsMenu(context, browserProvider)),
            IconButton(icon: const Icon(Iconsax.setting_2), onPressed: () {
               // Placeholder for more advanced settings
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Advanced Settings Locked (Enterprise Demo)")));
            }),
          ],
        ),
      ),
    );
  }

  void _showToolsMenu(BuildContext context, BrowserProvider provider) {
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
              Text("Enterprise Tools", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _ToolIcon(
                      icon: provider.isDesktopMode ? Icons.monitor : Icons.smartphone, 
                      label: provider.isDesktopMode ? "Mobile Site" : "Desktop Site",
                      isActive: provider.isDesktopMode,
                      onTap: () {
                        provider.toggleDesktopMode();
                        Navigator.pop(context);
                      },
                    ),
                    _ToolIcon(
                      icon: Iconsax.share, 
                      label: "Share",
                      onTap: () {
                        Share.share(provider.currentUrl);
                        Navigator.pop(context);
                      },
                    ),
                    _ToolIcon(
                      icon: Iconsax.eraser, 
                      label: "Clear Data",
                      onTap: () async {
                        await provider.clearBrowsingData();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cache & Cookies Cleared")));
                      },
                    ),
                    _ToolIcon(
                      icon: Iconsax.printer, 
                      label: "Print/PDF",
                      onTap: () {
                         Navigator.pop(context);
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Printing started...")));
                      },
                    ),
                     _ToolIcon(
                      icon: Iconsax.code, 
                      label: "View Source",
                      onTap: () {
                         Navigator.pop(context);
                         // Implementation would go here
                      },
                    ),
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
          Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
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
    final browserProvider = Provider.of<BrowserProvider>(context, listen: false); // Get current URL
    final textController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)
                  ),
                  child: const Icon(Iconsax.magic_star, color: Colors.blueAccent),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Enterprise Copilot", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text(browserProvider.currentUrl.length > 30 ? "${browserProvider.currentUrl.substring(0,30)}..." : browserProvider.currentUrl, 
                         style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: aiProvider.messages.length,
              itemBuilder: (context, index) {
                final msg = aiProvider.messages[index];
                final isBot = !msg.isUser;
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(16),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: msg.isUser 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isBot ? 4 : 20),
                        bottomRight: Radius.circular(isBot ? 20 : 4),
                      ),
                    ),
                    child: Text(
                      msg.text, 
                      style: TextStyle(
                        color: msg.isUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
                        height: 1.4
                      )
                    ),
                  ),
                );
              },
            ),
          ),
          if (aiProvider.isThinking)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)
                  ),
                  const SizedBox(width: 12),
                  const Text("Analyzing page data..."),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))]
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    decoration: InputDecoration(
                      hintText: "Ask about this page...",
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (value) {
                       if (value.isNotEmpty) {
                        aiProvider.sendMessage(value, browserProvider.currentUrl);
                        textController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  elevation: 0,
                  child: const Icon(Icons.send),
                  onPressed: () {
                    if (textController.text.isNotEmpty) {
                      aiProvider.sendMessage(textController.text, browserProvider.currentUrl);
                      textController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}