import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ble_log_service.dart';
import '../models/g2_constants.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Communication Log'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Consumer<BleLogService>(
            builder: (context, logService, _) => IconButton(
              icon: Icon(logService.isLogging ? Icons.pause : Icons.play_arrow),
              tooltip: logService.isLogging ? 'Pause Logging' : 'Resume Logging',
              onPressed: () => logService.toggleLogging(),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(context, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('Copy to Clipboard'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('Share Log'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.save),
                  title: Text('Export to File'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Clear Logs', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<BleLogService>(
        builder: (context, logService, child) {
          if (logService.logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No logs yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'BLE communication will be logged here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Log Stats Bar
              Container(
                color: Colors.grey[200],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      logService.isLogging ? Icons.fiber_manual_record : Icons.pause,
                      size: 12,
                      color: logService.isLogging ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${logService.logCount} entries',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      logService.isLogging ? 'Recording' : 'Paused',
                      style: TextStyle(
                        color: logService.isLogging ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Log List
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  itemCount: logService.logs.length,
                  itemBuilder: (context, index) {
                    // Show newest first
                    final entry = logService.logs[logService.logs.length - 1 - index];
                    return _LogEntryTile(entry: entry);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) async {
    final logService = Provider.of<BleLogService>(context, listen: false);

    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: logService.getFormattedLogs()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logs copied to clipboard')),
          );
        }
        break;

      case 'share':
        await Share.share(
          logService.getFormattedLogs(),
          subject: 'Even G2 BLE Log',
        );
        break;

      case 'export':
        try {
          final path = await logService.exportToFile();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Log saved to: $path')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Export failed: $e')),
            );
          }
        }
        break;

      case 'clear':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Logs?'),
            content: const Text('This will delete all logged entries.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  logService.clearLogs();
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        break;
    }
  }
}

class _LogEntryTile extends StatelessWidget {
  final BleLogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isSend = entry.direction == BleLogDirection.send;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Card(
        color: isSend ? Colors.blue[50] : Colors.green[50],
        child: InkWell(
          onTap: () => _showDetailDialog(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSend ? Colors.blue : Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isSend ? 'TX' : 'RX',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.characteristic,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}.${entry.timestamp.millisecond.toString().padLeft(3, '0')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.hexData,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.description!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              entry.direction == BleLogDirection.send ? Icons.arrow_upward : Icons.arrow_downward,
              color: entry.direction == BleLogDirection.send ? Colors.blue : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(entry.direction == BleLogDirection.send ? 'Sent Packet' : 'Received Packet'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('Time', entry.timestamp.toString()),
              _DetailRow('Characteristic', entry.characteristic),
              _DetailRow('Length', '${entry.data.length} bytes'),
              if (entry.description != null) _DetailRow('Description', entry.description!),
              const SizedBox(height: 8),
              const Text('Hex Data:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  entry.hexData,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: entry.hexData));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy Hex'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
