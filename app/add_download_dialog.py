import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# First, create the DownloadDialog class at the end of the file.
dialog_code = """
class DownloadDialog extends StatefulWidget {
  final String url;
  const DownloadDialog({super.key, required this.url});

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  double _progress = 0.0;
  String _downloaded = "0 MB";
  String _total = "0 MB";
  bool _isDownloading = true;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await http.Client().send(request);
      
      final contentLength = response.contentLength ?? 0;
      int receivedBytes = 0;
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/AutoRoomzio_update.apk');
      final sink = file.openWrite();

      response.stream.listen(
        (List<int> chunk) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          if (mounted) {
            setState(() {
              if (contentLength > 0) {
                _progress = receivedBytes / contentLength;
                _total = (contentLength / (1024 * 1024)).toStringAsFixed(1);
              }
              _downloaded = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            });
          }
        },
        onDone: () async {
          await sink.close();
          if (!mounted) return;
          setState(() { _isDownloading = false; });
          Navigator.pop(context);
          
          final result = await OpenFilex.open(file.path);
          if (result.type != ResultType.done) {
            // handle error if needed, but context might be dead.
          }
        },
        onError: (e) async {
          await sink.close();
          if (mounted) Navigator.pop(context);
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Téléchargement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_downloaded MB / $_total MB', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
"""

if "class DownloadDialog" not in content:
    content += "\n" + dialog_code

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)