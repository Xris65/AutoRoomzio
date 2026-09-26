import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  var content = file.readAsStringSync();

  // Add import if not exists
  if (!content.contains('package:package_info_plus/package_info_plus.dart')) {
    content = content.replaceFirst(
      'import ''package:flutter/material.dart'';',
      'import ''package:flutter/material.dart'';\nimport ''package:package_info_plus/package_info_plus.dart'';'
    );
  }

  // Replace version hardcoding with FutureBuilder
  content = content.replaceFirst(
    '''          child: const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),''',
    '''          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              return ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                trailing: Text(snapshot.hasData ? snapshot.data!.version : '...'),
              );
            },
          ),'''
  );
  
  // also try replacing with 1.1.0 just in case
  content = content.replaceFirst(
    '''          child: const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Version'),
            trailing: Text('1.1.0'),
          ),''',
    '''          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              return ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                trailing: Text(snapshot.hasData ? snapshot.data!.version : '...'),
              );
            },
          ),'''
  );

  file.writeAsStringSync(content);
}
