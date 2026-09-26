import 'dart:io';

void main() {
  final file = File('lib/screens/optimization_screen.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceAll('''Atre prAcvenu(e)''', '''être prévenu(e)''');
  content = content.replaceAll('''succA"s ou de l'Acchec''', '''succès ou de l'échec''');
  content = content.replaceAll('''rAcserver''', '''réserver''');
  content = content.replaceAll('''arriA"re-plan''', '''arrière-plan''');
  content = content.replaceAll('''EmpAche''', '''Empêche''');
  
  file.writeAsStringSync(content);
}
