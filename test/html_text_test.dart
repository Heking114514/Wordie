import 'package:english/util/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes html tags and decodes entities from translations', () {
    expect(
      cleanHtmlText(
        '这家饭店悬挂着欧盟的<b>旗帜</b>。&nbsp;&amp;&lt;ok&gt;',
      ),
      '这家饭店悬挂着欧盟的旗帜。 &<ok>',
    );
  });

  test('preserves bold markers only when requested for example text', () {
    expect(
      cleanHtmlText(
        'A <b>flag</b><br>is flying.',
        preserveBold: true,
      ),
      'A <b>flag</b>\nis flying.',
    );
  });
}
