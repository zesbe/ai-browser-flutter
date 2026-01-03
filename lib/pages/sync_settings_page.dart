import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../services/sync_service.dart';

// ============================================================================
// SYNC SETTINGS PAGE - Google Account & Sync Settings UI
// ============================================================================

class SyncSettingsPage extends StatefulWidget {
  final SyncService syncService;
  final Color accentColor;

  const SyncSettingsPage({
    super.key,
    required this.syncService,
    this.accentColor = Colors.amber,
  });

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Sync & Google Account',
          style: TextStyle(color: widget.accentColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.accentColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.syncService,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Section
                _buildAccountSection(),
                const SizedBox(height: 24),

                // Sync Status Section
                if (widget.syncService.isSignedIn) ...[
                  _buildSyncStatusSection(),
                  const SizedBox(height: 24),

                  // Sync Options
                  _buildSyncOptionsSection(),
                  const SizedBox(height: 24),

                  // Other Devices
                  _buildOtherDevicesSection(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // ACCOUNT SECTION
  // ============================================================================

  Widget _buildAccountSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.accentColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          if (syncService.isSignedIn) ...[
            // Signed In State
            Row(
              children: [
                // Profile Picture
                CircleAvatar(
                  radius: 32,
                  backgroundColor: widget.accentColor.withOpacity(0.2),
                  backgroundImage: syncService.userPhotoUrl != null
                      ? NetworkImage(syncService.userPhotoUrl!)
                      : null,
                  child: syncService.userPhotoUrl == null
                      ? Icon(Icons.person, color: widget.accentColor, size: 32)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncService.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        syncService.userEmail,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[300],
                  side: BorderSide(color: Colors.red[300]!.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            // Signed Out State
            Icon(
              Iconsax.cloud_add,
              size: 64,
              color: widget.accentColor.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sync with Google',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to sync your bookmarks, history, and settings across all your devices.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSignIn,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata),
                      ),
                label: Text(_isLoading ? 'Signing in...' : 'Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // SYNC STATUS SECTION
  // ============================================================================

  Widget _buildSyncStatusSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sync Status',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: syncService.syncEnabled,
                onChanged: (value) => syncService.setSyncEnabled(value),
                activeColor: widget.accentColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                syncService.isSyncing
                    ? Icons.sync
                    : syncService.syncError != null
                        ? Icons.sync_problem
                        : syncService.isOnline
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                color: syncService.syncError != null
                    ? Colors.red
                    : syncService.isOnline
                        ? Colors.green
                        : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncService.isSyncing
                      ? 'Syncing...'
                      : syncService.syncError ?? (
                          syncService.isOnline
                              ? (syncService.lastSyncTime != null
                                  ? 'Last synced: ${_formatLastSync(syncService.lastSyncTime!)}'
                                  : 'Ready to sync')
                              : 'Offline - Will sync when online'
                        ),
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (!syncService.isSyncing) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => syncService.syncNow(),
              icon: Icon(Icons.sync, color: widget.accentColor, size: 18),
              label: Text(
                'Sync Now',
                style: TextStyle(color: widget.accentColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // SYNC OPTIONS SECTION
  // ============================================================================

  Widget _buildSyncOptionsSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What to Sync',
            style: TextStyle(
              color: widget.accentColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSyncOption(
            icon: Iconsax.bookmark,
            title: 'Bookmarks',
            subtitle: 'Sync your saved bookmarks',
            value: syncService.syncBookmarks,
            onChanged: (v) => syncService.updateSyncSetting('bookmarks', v),
          ),
          _buildSyncOption(
            icon: Iconsax.clock,
            title: 'History',
            subtitle: 'Sync your browsing history',
            value: syncService.syncHistory,
            onChanged: (v) => syncService.updateSyncSetting('history', v),
          ),
          _buildSyncOption(
            icon: Iconsax.book,
            title: 'Reading List',
            subtitle: 'Sync your reading list items',
            value: syncService.syncReadingList,
            onChanged: (v) => syncService.updateSyncSetting('reading_list', v),
          ),
          _buildSyncOption(
            icon: Iconsax.setting_2,
            title: 'Settings',
            subtitle: 'Sync browser preferences',
            value: syncService.syncSettings,
            onChanged: (v) => syncService.updateSyncSetting('settings', v),
          ),
          _buildSyncOption(
            icon: Iconsax.document,
            title: 'Open Tabs',
            subtitle: 'See tabs from other devices',
            value: syncService.syncOpenTabs,
            onChanged: (v) => syncService.updateSyncSetting('open_tabs', v),
          ),
          _buildSyncOption(
            icon: Iconsax.key,
            title: 'Passwords',
            subtitle: 'Sync saved passwords (encrypted)',
            value: syncService.syncPasswords,
            onChanged: (v) => syncService.updateSyncSetting('passwords', v),
            isSecure: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isSecure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: widget.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    if (isSecure) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.shield, color: Colors.green[400], size: 14),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: widget.syncService.syncEnabled ? onChanged : null,
            activeColor: widget.accentColor,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // OTHER DEVICES SECTION
  // ============================================================================

  Widget _buildOtherDevicesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Other Devices',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: widget.accentColor, size: 20),
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
            future: widget.syncService.getOtherDevicesTabs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final devices = snapshot.data ?? {};

              if (devices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Iconsax.mobile,
                        size: 40,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No other devices found',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in on another device to see tabs here',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: devices.entries.map((entry) {
                  return ExpansionTile(
                    leading: Icon(Iconsax.monitor, color: widget.accentColor),
                    title: Text(
                      entry.key,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${entry.value.length} tabs',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    children: entry.value.map((tab) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.tab, size: 16),
                        title: Text(
                          tab['title'] ?? 'Untitled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          tab['url'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        onTap: () {
                          // Open this tab
                          Navigator.pop(context, tab['url']);
                        },
                      );
                    }).toList(),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HANDLERS
  // ============================================================================

  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    final success = await widget.syncService.signInWithGoogle();
    setState(() => _isLoading = false);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.syncService.syncError ?? 'Sign in failed'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Sign Out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your data will remain on this device but will no longer sync.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await widget.syncService.signOut();
      setState(() => _isLoading = false);
    }
  }

  String _formatLastSync(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
