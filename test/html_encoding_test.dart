import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/src/services/email_parser.dart';
import 'package:test/test.dart';

void main() {
  group('EmailParser HTML encoding', () {
    late EmailParser parser;

    setUp(() {
      parser = EmailParser();
    });

    test('HTML part should not have broken tags due to line wrapping', () {
      // Simulate HTML from Quill converter with PGP message
      const htmlContent =
          '<p>-----BEGIN PGP MESSAGE-----<br/><br/>hQIMA8u18CNK8VwJAQ//VgyOWTcCPOX74NrNXO28w8GKFwxzD1v0HMQlRtsyYEu8<br/>Dj7kjHinao8R9pErJpMT3umg0J653Uf9aBhEfkuS38Mfu2W/CoHlsHz5acO8XNmr<br/>pHhvFOsiEytRBySFR9Hix8D2fPGxsrcdcTp6HOK8TpqEF6v/hahErrW8Z/V6PTOG<br/>whnxGJWriYj5GPRk1WlvLA+KTafC2Gy429uYCTzM6XQBvT74WXqih8EiQ1yiksmi<br/>j160OiZ2d2k6eRqaGGqR5BRYNgLF7CGTP04wz/fkyKx4UqhpNnVoTlt+SerbUm6i<br/>LUDvmVSIpnd+gsaqDXmufApvWkTAgy1ftc2ZSOsaFyD4yLxtq44N8V393fFmtKOR<br/>N4HV6K+jP3bVL0YO+FZI9bQuIOvwlYBqDA9HvGRmmKJgA88xLejedPkxH9dao0tU<br/>+AFJ3Uzhm7nJkoQReaMkVy0uzOxi4LhHLhF2uiih2MZ2uGjjh36c+CSr8Ng3jsGp<br/>FEO3ffxbmpze8TyQCrFVVTImbfsmAsbrudVwPWEcMgF1loYflaQe4KJM+eeXRiA9<br/>pqYyLW83xzdGNfROfLKSzhWM8WLNIAYj+ml5u/Jr8ViDLru1q2RxP4/8YrBqYn5l<br/>Vwf5vwgbMhVSONB64KBLYMR80tBHH7bxNLeLBDtWpR//zPvkwR4b+h+PX6wfY5OE<br/>XgMj/CQJ2szaehIBB0AIt9xGY39q5/DsRqFVm4+o9pi3XNkfqgNWIcfT5NweOzD4<br/>UU7kBsX9GmYV90M3+5cTe4tAg8t6P5Mj7NbiOGQ6tQKkhAfemtbp0fq5Cixh6lPS<br/>wT0BaoClElYIcUVq0EfEPDGGFrzxRS51HTb3AREZnC4ewtF3K4gDbVs8J47CK9c/<br/>zBeOW2pv7zdjtsdJxWaYzl9ZoSFJZSdCHvmjJcborohVZ9cR3lTkley9op9Rg4TZ<br/>sMnj2isNZUlYEVWLX1HCEo/otP9OeQ2p1caAw+3N/r5ix6dJaxSaETSJZzNUKEK+<br/>C2ULQE48p4lrnq8qnK6NPgCS14OV/J1CUBx5hawwY46lNDv6ArA6NwmYiHWO49v6<br/>qOo7rS3K41maTNfMVDvb/1TC3KREQX9Su+X4QCfkvqa4nWlLTmbBBYEAbrvw+exj<br/>PmkVQHppyz+/VHvyF1qTw44NTxu/iQdNNER9a0XAflsrHB4JDd8j6Bg5xyGy5Kxa<br/>WXtsdlSF7tINEPUb1cu3ga3f+X1GRxNjK7cn1fXuPCvCTGWTXa3/6AONSpH2B0bl<br/>LOVRyWNAtGw2h/ZeWj/gW3ooW5zW4/XKGPmW30wHs8gaH6SEfYtwn/9h1TztR6qp<br/>eEJeY2jsdviQcddNzVYNt1H4VGujHIKgVkGtwhwGnTFfWaYJ9lDjYrDGQOz8qlDf<br/>jgStoRn1te83dPMkIiR0D8k2qOsc3O9AHgjryrUwJ+5lhzNaNPAdylP2F2QSizNv<br/>sKQmvStoVdU+VNawnajZXVFZTJgCNRAwL7Q0NJB25Q==<br/>=6EE/<br/>-----END PGP MESSAGE-----</p>';

      final rawContent = parser.build(
        from: MailAddress(null, 'sender@nostr.com'),
        to: [MailAddress(null, 'recipient@example.com')],
        subject: 'PGP Message',
        body: 'PGP content',
        htmlBody: htmlContent,
      );

      print('MIME output:\n$rawContent');

      expect(
        rawContent.contains('<\r\nbr/>') || rawContent.contains('<\nbr/>'),
        isFalse,
        reason: 'HTML tags should not be split across lines',
      );
    });

    test('HTML with long lines should use proper encoding', () {
      const longLine =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final htmlContent = '<p>$longLine<br/>$longLine</p>';

      final rawContent = parser.build(
        from: MailAddress(null, 'sender@nostr.com'),
        to: [MailAddress(null, 'recipient@example.com')],
        subject: 'Test',
        body: 'Plain text',
        htmlBody: htmlContent,
      );

      print('MIME output:\n$rawContent');

      expect(
        rawContent.contains('Content-Transfer-Encoding: quoted-printable') ||
            rawContent.contains('Content-Transfer-Encoding: base64'),
        isTrue,
        reason: 'HTML content should use quoted-printable or base64 encoding',
      );
    });
  });
}
