import 'dart:io';
void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst('Text(''1.0.0'')', 'Text(''1.1.0'')');
  file.writeAsStringSync(content);
}
