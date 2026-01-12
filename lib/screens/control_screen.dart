import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/ble_service.dart';
import '../services/g2_protocol.dart';
import '../widgets/ai_chat_widget.dart';
import 'scan_screen.dart';
import 'log_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Even G2 Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.article),
            tooltip: 'View Logs',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble), text: 'AI'),
            Tab(icon: Icon(Icons.text_fields), text: 'Text'),
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.navigation), text: 'Navigation'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          if (!bleService.isConnected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
            });
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Connection Status
              _ConnectionStatusBar(bleService: bleService),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    AiChatWidget(bleService: bleService),
                    _TeleprompterTab(bleService: bleService),
                    _DashboardTab(bleService: bleService),
                    _NavigationTab(bleService: bleService),
                    _SettingsTab(bleService: bleService),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionStatusBar extends StatelessWidget {
  final BleService bleService;

  const _ConnectionStatusBar({required this.bleService});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.green[100],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bleService.connectedDeviceName ?? "Even G2",
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await bleService.disconnect();
            },
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Disconnect'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Teleprompter Tab =====
class _TeleprompterTab extends StatefulWidget {
  final BleService bleService;

  const _TeleprompterTab({required this.bleService});

  @override
  State<_TeleprompterTab> createState() => _TeleprompterTabState();
}

class _TeleprompterTabState extends State<_TeleprompterTab> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _textController.text = 'こんにちは、Even G2!\n\nFlutterアプリからのテストメッセージです。';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    if (_textController.text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await widget.bleService.sendTeleprompterText(_textController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('送信しました！'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('テレプロンプター', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'テキストを入力...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(label: const Text('Hello'), onPressed: () => _textController.text = 'Hello, World!'),
              ActionChip(label: const Text('Time'), onPressed: () => _textController.text = '現在時刻: ${DateFormat('HH:mm:ss').format(DateTime.now())}'),
              ActionChip(label: const Text('Clear'), onPressed: () => _textController.clear()),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSending ? null : _sendText,
            icon: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_isSending ? '送信中...' : 'メガネに送信'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }
}

// ===== Dashboard Tab =====
class _DashboardTab extends StatefulWidget {
  final BleService bleService;

  const _DashboardTab({required this.bleService});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  bool _isSending = false;
  String _weather = '晴れ';
  int _temperature = 22;

  Future<void> _sendDashboard() async {
    setState(() => _isSending = true);
    try {
      final now = DateTime.now();
      await widget.bleService.sendDashboard(
        time: DateFormat('HH:mm').format(now),
        date: DateFormat('M月d日 (E)', 'ja').format(now),
        weather: _weather,
        temperature: _temperature,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ダッシュボード送信！'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ダッシュボード', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Time Preview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    DateFormat('HH:mm').format(DateTime.now()),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    DateFormat('yyyy年M月d日 (EEEE)', 'ja').format(DateTime.now()),
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Weather Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('天気', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['晴れ', '曇り', '雨', '雪'].map((w) {
                      return ChoiceChip(
                        label: Text(w),
                        selected: _weather == w,
                        onSelected: (_) => setState(() => _weather = w),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Temperature Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('気温: $_temperature°C', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _temperature.toDouble(),
                    min: -10,
                    max: 40,
                    divisions: 50,
                    label: '$_temperature°C',
                    onChanged: (v) => setState(() => _temperature = v.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isSending ? null : _sendDashboard,
            icon: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.dashboard),
            label: Text(_isSending ? '送信中...' : 'ダッシュボード表示'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }
}

// ===== Navigation Tab =====
class _NavigationTab extends StatefulWidget {
  final BleService bleService;

  const _NavigationTab({required this.bleService});

  @override
  State<_NavigationTab> createState() => _NavigationTabState();
}

class _NavigationTabState extends State<_NavigationTab> {
  bool _isSending = false;
  NavigationDirection _direction = NavigationDirection.straight;
  String _distance = '100m';
  String _streetName = '国道1号線';

  final Map<NavigationDirection, String> _directionLabels = {
    NavigationDirection.straight: '直進',
    NavigationDirection.slightRight: '斜め右',
    NavigationDirection.right: '右折',
    NavigationDirection.sharpRight: '急右折',
    NavigationDirection.uTurn: 'Uターン',
    NavigationDirection.sharpLeft: '急左折',
    NavigationDirection.left: '左折',
    NavigationDirection.slightLeft: '斜め左',
    NavigationDirection.arrived: '到着',
  };

  Future<void> _sendNavigation() async {
    setState(() => _isSending = true);
    try {
      await widget.bleService.sendNavigation(
        direction: _direction,
        distance: _distance,
        streetName: _streetName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ナビゲーション送信！'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ナビゲーション', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Direction Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('方向', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: NavigationDirection.values.map((d) {
                      return ChoiceChip(
                        label: Text(_directionLabels[d]!),
                        selected: _direction == d,
                        onSelected: (_) => setState(() => _direction = d),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Distance Input
          TextField(
            decoration: const InputDecoration(
              labelText: '距離',
              hintText: '例: 100m, 1.5km',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _distance),
            onChanged: (v) => _distance = v,
          ),
          const SizedBox(height: 16),

          // Street Name Input
          TextField(
            decoration: const InputDecoration(
              labelText: '道路名',
              hintText: '例: 国道1号線',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _streetName),
            onChanged: (v) => _streetName = v,
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isSending ? null : _sendNavigation,
            icon: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.navigation),
            label: Text(_isSending ? '送信中...' : 'ナビゲーション表示'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ],
      ),
    );
  }
}

// ===== Settings Tab =====
class _SettingsTab extends StatefulWidget {
  final BleService bleService;

  const _SettingsTab({required this.bleService});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  int _brightness = 50;
  int _positionX = 0;
  int _positionY = 0;

  Future<void> _setBrightness() async {
    try {
      await widget.bleService.setBrightness(_brightness);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('明るさ: $_brightness%'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setPosition() async {
    try {
      await widget.bleService.setPosition(x: _positionX, y: _positionY);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('位置: ($_positionX, $_positionY)'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearDisplay() async {
    try {
      await widget.bleService.clearDisplay();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画面クリア'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('設定', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // Brightness
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.brightness_6),
                      const SizedBox(width: 8),
                      Text('明るさ: $_brightness%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _brightness.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_brightness%',
                    onChanged: (v) => setState(() => _brightness = v.round()),
                    onChangeEnd: (_) => _setBrightness(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Position
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.open_with),
                      const SizedBox(width: 8),
                      Text('表示位置: ($_positionX, $_positionY)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('X:'),
                      Expanded(
                        child: Slider(
                          value: _positionX.toDouble(),
                          min: -50,
                          max: 50,
                          divisions: 20,
                          onChanged: (v) => setState(() => _positionX = v.round()),
                          onChangeEnd: (_) => _setPosition(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Y:'),
                      Expanded(
                        child: Slider(
                          value: _positionY.toDouble(),
                          min: -50,
                          max: 50,
                          divisions: 20,
                          onChanged: (v) => setState(() => _positionY = v.round()),
                          onChangeEnd: (_) => _setPosition(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('クイックアクション', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _clearDisplay,
                        icon: const Icon(Icons.clear),
                        label: const Text('画面クリア'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await widget.bleService.activateDisplay();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('ディスプレイON'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.tv),
                        label: const Text('ディスプレイON'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
