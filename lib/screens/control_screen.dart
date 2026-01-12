import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'scan_screen.dart';
import 'log_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _textController.text = 'Hello, Even G2!\n\nThis is a test message from the Flutter app.\n\nYou can display any text on your smart glasses using the teleprompter feature.';
  }

  @override
  void dispose() {
    _textController.dispose();
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
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          // Check connection state
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
              Container(
                color: Colors.green[100],
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connected to: ${bleService.connectedDeviceName ?? "Even G2"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await bleService.disconnect();
                      },
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Disconnect'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ),

              // Teleprompter Section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Teleprompter',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter text to display on your Even G2 glasses',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 16),

                      // Text Input
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'Enter your text here...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Quick Text Buttons
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _QuickTextChip(
                              label: 'Hello',
                              onTap: () => _textController.text = 'Hello, World!',
                            ),
                            _QuickTextChip(
                              label: 'Time',
                              onTap: () => _textController.text =
                                  'Current time:\n${DateTime.now().toString().substring(0, 19)}',
                            ),
                            _QuickTextChip(
                              label: 'Test',
                              onTap: () => _textController.text =
                                  'This is a test message.\n\nLine 1\nLine 2\nLine 3\nLine 4\nLine 5',
                            ),
                            _QuickTextChip(
                              label: 'Clear',
                              onTap: () => _textController.clear(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Send Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSending
                              ? null
                              : () => _sendText(context, bleService),
                          icon: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                          label: Text(_isSending ? 'Sending...' : 'Send to Glasses'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendText(BuildContext context, BleService bleService) async {
    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some text')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await bleService.sendTeleprompterText(_textController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Text sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }
}

class _QuickTextChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickTextChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }
}
