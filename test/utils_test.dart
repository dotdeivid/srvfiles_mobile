import 'package:flutter_test/flutter_test.dart';
import 'package:srvfiles_mobile/utils/format.dart';
import 'package:srvfiles_mobile/utils/file_icons.dart';

void main() {
  group('formatBytes', () {
    test('0 bytes', () {
      expect(formatBytes(0), '0 B');
    });

    test('bytes', () {
      expect(formatBytes(500), '500 B');
    });

    test('kilobytes', () {
      expect(formatBytes(1024), '1 KB');
    });

    test('kilobytes with decimal', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('megabytes', () {
      expect(formatBytes(1048576), '1 MB');
    });

    test('gigabytes', () {
      expect(formatBytes(1073741824), '1 GB');
    });

    test('large megabytes', () {
      expect(formatBytes(5242880), '5 MB');
    });

    test('decimal megabytes', () {
      // 2.5 MB = 2621440
      expect(formatBytes(2621440), '2.5 MB');
    });
  });

  group('getFileIcon', () {
    test('pdf', () {
      expect(getFileIcon('document.pdf'), '📄');
    });

    test('jpg', () {
      expect(getFileIcon('photo.jpg'), '🖼️');
    });

    test('jpeg', () {
      expect(getFileIcon('photo.jpeg'), '🖼️');
    });

    test('png', () {
      expect(getFileIcon('image.png'), '🖼️');
    });

    test('mp4', () {
      expect(getFileIcon('video.mp4'), '🎬');
    });

    test('mp3', () {
      expect(getFileIcon('song.mp3'), '🎵');
    });

    test('zip', () {
      expect(getFileIcon('archive.zip'), '📦');
    });

    test('js', () {
      expect(getFileIcon('script.js'), '⚙️');
    });

    test('html', () {
      expect(getFileIcon('page.html'), '🌐');
    });

    test('xlsx', () {
      expect(getFileIcon('data.xlsx'), '📊');
    });

    test('doc', () {
      expect(getFileIcon('note.doc'), '📝');
    });

    test('unknown extension returns default', () {
      expect(getFileIcon('file.xyz'), '📁');
    });

    test('no extension returns default', () {
      expect(getFileIcon('README'), '📁');
    });

    test('case insensitive', () {
      expect(getFileIcon('Photo.JPG'), '🖼️');
      expect(getFileIcon('Video.MP4'), '🎬');
    });

    test('dot at end returns default', () {
      expect(getFileIcon('file.'), '📁');
    });
  });
}
