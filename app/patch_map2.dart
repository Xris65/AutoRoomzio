import 'dart:io';

void main() {
  final file = File('lib/widgets/workspace_map_viewer.dart');
  var content = file.readAsStringSync();
  
  // Convert all \r\n to \n to make replacements easy!
  content = content.replaceAll('\r\n', '\n');

  content = content.replaceFirst(
    '''        void processPoint(List p) {
          if (p.length < 2) return;
          final x = (p[0] as num).toDouble();
          final y = (p[1] as num).toDouble();
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }

        if (type == 'Point') {
          processPoint(coords);
        } else {
          for (var point in coords) {
            if (point is List) processPoint(point);
          }
        }''',
    '''        void extractPoints(List list) {
          if (list.isEmpty) return;
          if (list[0] is num) {
            if (list.length >= 2) {
              final x = (list[0] as num).toDouble();
              final y = (list[1] as num).toDouble();
              if (x < minX) minX = x;
              if (y < minY) minY = y;
              if (x > maxX) maxX = x;
              if (y > maxY) maxY = y;
            }
          } else {
            for (var item in list) {
              if (item is List) extractPoints(item);
            }
          }
        }
        extractPoints(coords);'''
  );

  content = content.replaceFirst(
    '''                void processFeaturePoint(List p) {
                  if (p.length < 2) return;
                  final x = (p[0] as num).toDouble();
                  final y = (p[1] as num).toDouble();
                  if (x < fMinX) fMinX = x;
                  if (y < fMinY) fMinY = y;
                  if (x > fMaxX) fMaxX = x;
                  if (y > fMaxY) fMaxY = y;
                }

                if (type == 'Point') {
                  processFeaturePoint(coords);
                } else {
                  for (var point in coords) {
                    if (point is List) processFeaturePoint(point);
                  }
                }''',
    '''                void extractFeaturePoints(List list) {
                  if (list.isEmpty) return;
                  if (list[0] is num) {
                    if (list.length >= 2) {
                      final x = (list[0] as num).toDouble();
                      final y = (list[1] as num).toDouble();
                      if (x < fMinX) fMinX = x;
                      if (y < fMinY) fMinY = y;
                      if (x > fMaxX) fMaxX = x;
                      if (y > fMaxY) fMaxY = y;
                    }
                  } else {
                    for (var item in list) {
                      if (item is List) extractFeaturePoints(item);
                    }
                  }
                }
                extractFeaturePoints(coords);'''
  );

  content = content.replaceAll('if (scale > 5.0) scale = 5.0;', 'if (scale > 100.0) scale = 100.0;');
  content = content.replaceAll('maxScale: 5.0,', 'maxScale: 100.0,');

  file.writeAsStringSync(content);
}
