import 'dart:io';
void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(r'\n', '\n');
  file.writeAsStringSync(content);
}
