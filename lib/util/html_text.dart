String cleanHtmlText(String value, {bool preserveBold = false}) {
  var text = value;
  if (preserveBold) {
    text = text.replaceAllMapped(
      RegExp(r'<b>(.*?)</b>', dotAll: true, caseSensitive: false),
      (match) => '[[B]]${match.group(1)}[[/B]]',
    );
  }
  text = text
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  if (preserveBold) {
    text = text.replaceAll('[[B]]', '<b>').replaceAll('[[/B]]', '</b>');
  }
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}
