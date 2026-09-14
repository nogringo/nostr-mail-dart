import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/src/utils/body_preview.dart';
import 'package:nostr_mail/src/utils/html_to_text.dart';
import 'package:test/test.dart';

MimeMessage _message({String? plain, String? html}) {
  final builder = MessageBuilder.prepareMultipartAlternativeMessage()
    ..from = [MailAddress(null, 'a@example.com')]
    ..to = [MailAddress(null, 'b@example.com')]
    ..subject = 'Subject';
  if (plain != null) builder.addTextPlain(plain);
  if (html != null) builder.addTextHtml(html);
  return builder.buildMimeMessage();
}

void main() {
  group('htmlToText', () {
    test('keeps one line per block and per br', () {
      expect(
        htmlToText('<p>Hello<br/>world</p><div>Next</div>'),
        'Hello\nworld\nNext',
      );
    });

    test('collapses markup whitespace', () {
      expect(
        htmlToText('<p>\n  Hello\n   <b>big</b>  world\n</p>'),
        'Hello big world',
      );
    });

    test('shows a link target only when it differs from its text', () {
      expect(
        htmlToText(
          '<a href="https://nostrmail.org">https://nostrmail.org</a> '
          '<a href="https://example.com/doc">the doc</a> '
          '<a href="mailto:bob@example.com">bob@example.com</a>',
        ),
        'https://nostrmail.org the doc <https://example.com/doc> bob@example.com',
      );
    });

    test('marks list items and numbers ordered ones', () {
      expect(
        htmlToText(
          '<ul><li>one</li><li>two</li></ul><ol><li>a</li><li>b</li></ol>',
        ),
        '* one\n* two\n1. a\n2. b',
      );
    });

    test('prefixes quoted lines', () {
      expect(
        htmlToText(
          '<p>Reply</p><blockquote><p>line 1</p><p>line 2</p></blockquote>',
        ),
        'Reply\n> line 1\n> line 2',
      );
    });

    test('leaves out styles, scripts and the head', () {
      expect(
        htmlToText(
          '<html><head><title>T</title><style>p{color:red}</style></head>'
          '<body><style>.x{}</style><p>Body</p><script>alert(1)</script></body></html>',
        ),
        'Body',
      );
    });

    test('keeps hidden preheader text', () {
      expect(
        htmlToText('<div style="display:none">Preheader</div><p>Body</p>'),
        'Preheader\nBody',
      );
    });

    test('decodes entities and non-breaking spaces', () {
      expect(htmlToText('<p>Tom&nbsp;&amp;&nbsp;Jerry</p>'), 'Tom & Jerry');
    });

    test('writes a signature delimiter with its trailing space', () {
      expect(htmlToText('<p>Hi<br/>--<br/>Alice</p>'), 'Hi\n-- \nAlice');
    });

    test('keeps preformatted whitespace', () {
      expect(htmlToText('<pre>a\n  b</pre>'), 'a\n  b');
    });
  });

  group('textPreview', () {
    test('joins lines and drops the signature', () {
      expect(
        textPreview('Hello\nsee you\n\n-- \nAlice\nhttps://alice.example'),
        'Hello see you',
      );
    });

    test('accepts a delimiter without its trailing space', () {
      expect(textPreview('Hi\n--\nSent with Nmail'), 'Hi');
    });

    test('is empty when only a signature is left', () {
      expect(textPreview('--\nSent with Nmail\nhttps://nostrmail.org'), '');
    });

    test('drops quoted lines and their attribution', () {
      expect(
        textPreview(
          'Sounds good.\n\nOn Mon, Sep 14, 2026, Bob <bob@example.com> wrote:\n\n'
          '> Shall we meet?\n> Tomorrow?',
        ),
        'Sounds good.',
      );
    });

    test('keeps replies interleaved with quotes', () {
      expect(
        textPreview('> Shall we meet?\nYes.\n> Where?\nHere:\n\nat the cafe'),
        'Yes. Here: at the cafe',
      );
    });

    test('cuts at the limit without splitting a surrogate pair', () {
      expect(textPreview('ab😀cd', maxLength: 3), 'ab');
      expect(textPreview('abcdef', maxLength: 3), 'abc');
    });
  });

  group('bodyPreview', () {
    test('reads the rendered HTML over a markdown text part', () {
      final message = _message(
        plain:
            'test dans 1 heure\n\n\\-\\-\nSent with Nmail\n'
            '[https://nostrmail\\.org](https://nostrmail.org)',
        html:
            '<p>test dans 1 heure<br/><br/>--<br/>Sent with Nmail<br/>'
            '<a href="https://nostrmail.org">https://nostrmail.org</a></p>',
      );
      expect(bodyPreview(message), 'test dans 1 heure');
    });

    test('falls back to the text part', () {
      expect(
        bodyPreview(_message(plain: 'Plain only\n-- \nsig')),
        'Plain only',
      );
    });
  });
}
