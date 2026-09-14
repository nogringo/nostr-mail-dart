import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Renders [html] as the plain text a reader sees: one line per block, links
/// as `text <url>`, list items as `* ` or `1. `, quotes prefixed with `> `,
/// and a `--` line as the `-- ` signature delimiter.
String htmlToText(String html) {
  final body = html_parser.parse(html).body;
  if (body == null) return '';
  return _TextWriter().write(body.nodes);
}

const _skipped = {'head', 'style', 'script', 'title', 'template', 'noscript'};

const _blocks = {
  'address',
  'article',
  'aside',
  'blockquote',
  'center',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'tfoot',
  'thead',
  'tr',
  'ul',
};

final _htmlWhitespace = RegExp(r'[ \t\n\r\f]+');

class _TextWriter {
  final _out = StringBuffer();
  bool _atLineStart = true;
  bool _inPre = false;

  String write(List<Node> nodes) {
    _nodes(nodes);
    return _out
        .toString()
        .replaceAll('\u00a0', ' ')
        .split('\n')
        .map((line) => line.trimRight())
        // RFC 3676 section 4.3: the signature delimiter keeps its space.
        .map((line) => line == '--' ? '-- ' : line)
        .join('\n')
        .replaceFirst(RegExp(r'\n+$'), '');
  }

  void _nodes(List<Node> nodes) {
    for (final node in nodes) {
      if (node is Text) {
        _text(node.data);
      } else if (node is Element) {
        _element(node);
      }
    }
  }

  void _text(String data) {
    if (_inPre) {
      _emit(data);
      return;
    }
    var text = data.replaceAll(_htmlWhitespace, ' ');
    if (_atLineStart) text = text.trimLeft();
    _emit(text);
  }

  void _emit(String text) {
    if (text.isEmpty) return;
    _out.write(text);
    _atLineStart = text.endsWith('\n');
  }

  void _breakLine() {
    if (_atLineStart) return;
    _out.write('\n');
    _atLineStart = true;
  }

  void _element(Element element) {
    final tag = element.localName;
    if (_skipped.contains(tag)) return;

    switch (tag) {
      case 'br':
        _out.write('\n');
        _atLineStart = true;
        return;
      case 'hr':
        _breakLine();
        _emit('---\n');
        return;
      case 'img':
        _text(element.attributes['alt'] ?? '');
        return;
      case 'a':
        _link(element);
        return;
      case 'blockquote':
        _prefixed(element.nodes, first: '> ', rest: '> ');
        return;
      case 'ol' || 'ul':
        _list(element);
        return;
      case 'td' || 'th':
        if (element.previousElementSibling != null) _emit(' ');
        _nodes(element.nodes);
        return;
    }

    final block = _blocks.contains(tag);
    if (block) _breakLine();
    final wasPre = _inPre;
    if (tag == 'pre') _inPre = true;
    _nodes(element.nodes);
    _inPre = wasPre;
    if (block) _breakLine();
  }

  void _link(Element element) {
    final text = _TextWriter().write(element.nodes).trim();
    final href = element.attributes['href']?.trim() ?? '';
    final target = href.startsWith('mailto:') ? href.substring(7) : href;
    final showsTarget =
        target.isNotEmpty &&
        !href.startsWith('#') &&
        text != target &&
        text != href;
    if (text.isEmpty) {
      _text(target);
    } else if (showsTarget) {
      _text('$text <$target>');
    } else {
      _text(text);
    }
  }

  void _list(Element list) {
    final ordered = list.localName == 'ol';
    var index = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    _breakLine();
    for (final item in list.children) {
      if (item.localName != 'li') {
        _element(item);
        continue;
      }
      final marker = ordered ? '${index++}. ' : '* ';
      _prefixed(item.nodes, first: marker, rest: ' ' * marker.length);
    }
  }

  void _prefixed(
    List<Node> nodes, {
    required String first,
    required String rest,
  }) {
    final lines = (_TextWriter().._inPre = _inPre).write(nodes).split('\n');
    _breakLine();
    for (var i = 0; i < lines.length; i++) {
      final prefix = i == 0 ? first : rest;
      final line = lines[i];
      _out.write(line.isEmpty ? '${prefix.trimRight()}\n' : '$prefix$line\n');
    }
    _atLineStart = true;
  }
}
