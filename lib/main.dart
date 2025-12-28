import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';

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
      title: 'AI Agent Browser',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Providers ---

class BrowserProvider extends ChangeNotifier {
  InAppWebViewController? webViewController;
  String currentUrl = "https://www.google.com";
  double progress = 0;
  bool isLoading = false;
  TextEditingController urlController = TextEditingController(text: "https://www.google.com");

  void setController(InAppWebViewController controller) {
    webViewController = controller;
  }

  void updateUrl(String url) {
    currentUrl = url;
    urlController.text = url;
    notifyListeners();
  }

  void updateProgress(double p) {
    progress = p;
    isLoading = p < 1.0;
    notifyListeners();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      url = "https://www.google.com/search?q=$url";
    }
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void goBack() {
    webViewController?.goBack();
  }

  void goForward() {
    webViewController?.goForward();
  }

  void reload() {
    webViewController?.reload();
  }
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [
    ChatMessage(
      text: "Hello! I am your AI Browser Agent. I can help you summarize pages, find information, or just chat. How can I help?",
      isUser: false,
    ),
  ];
  bool isThinking = false;

  void sendMessage(String text) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();

    // Simulate AI delay and response
    await Future.delayed(const Duration(seconds: 1));
    
    String response = "I analyzed the context of your browsing. That's interesting!";
    if (text.toLowerCase().contains("summarize")) {
      response = "Here is a summary of the current page content based on the visible text...";
    } else if (text.toLowerCase().contains("code")) {
      response = "I found some code snippets on this page. Would you like me to extract them?";
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
      body: SafeArea(
        child: Column(
          children: [
            // Address Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Iconsax.arrow_left_2),
                    onPressed: browserProvider.goBack,
                  ),
                  IconButton(
                    icon: const Icon(Iconsax.arrow_right_3),
                    onPressed: browserProvider.goForward,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: browserProvider.urlController,
                      decoration: InputDecoration(
                        hintText: "Search or enter address",
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                      ),
                      onSubmitted: (value) {
                        browserProvider.loadUrl(value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Iconsax.refresh),
                    onPressed: browserProvider.reload,
                  ),
                ],
              ),
            ),
            if (browserProvider.isLoading)
              LinearProgressIndicator(value: browserProvider.progress),
            
            // WebView
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri("https://www.google.com")),
                onWebViewCreated: (controller) {
                  browserProvider.setController(controller);
                },
                onLoadStart: (controller, url) {
                  browserProvider.updateUrl(url.toString());
                },
                onLoadStop: (controller, url) async {
                  browserProvider.updateProgress(1.0);
                  browserProvider.updateUrl(url.toString());
                },
                onProgressChanged: (controller, progress) {
                  browserProvider.updateProgress(progress / 100);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const AiAgentPanel(),
          );
        },
        icon: const Icon(Iconsax.magic_star),
        label: const Text("AI Agent"),
      ),
    );
  }
}

class AiAgentPanel extends StatelessWidget {
  const AiAgentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final aiProvider = Provider.of<AiAgentProvider>(context);
    final textController = TextEditingController();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Iconsax.magic_star, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Text(
                  "AI Assistant",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: aiProvider.messages.length,
              itemBuilder: (context, index) {
                final msg = aiProvider.messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isUser 
                        ? Theme.of(context).colorScheme.primaryContainer 
                        : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: msg.isUser ? const Radius.circular(0) : null,
                        bottomLeft: !msg.isUser ? const Radius.circular(0) : null,
                      ),
                    ),
                    child: Text(msg.text),
                  ),
                );
              },
            ),
          ),
          if (aiProvider.isThinking)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("AI is thinking...", style: TextStyle(fontStyle: FontStyle.italic)),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    decoration: InputDecoration(
                      hintText: "Ask something...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        aiProvider.sendMessage(value);
                        textController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    if (textController.text.isNotEmpty) {
                      aiProvider.sendMessage(textController.text);
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
