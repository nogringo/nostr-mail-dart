import 'dart:typed_data';

import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:http/http.dart' as http;
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('Signature images', () {
    late MockRelay relay;
    late MockBlossomServer blossom;
    late String blossomUrl;
    late TestUser phone;
    late TestUser desktop;

    final png = Uint8List.fromList(List.generate(300, (i) => i % 256));

    var runs = 0;

    setUp(() async {
      final run = runs++;
      relay = MockRelay(name: 'relay');
      await relay.startServer();
      addTearDown(relay.stopServer);
      blossom = MockBlossomServer(port: 3460);
      await blossom.start();
      addTearDown(blossom.stop);
      blossomUrl = 'http://localhost:${blossom.port}';

      phone = await TestUser(
        'signature_images_phone_$run',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [blossomUrl],
      ).create();
      addTearDown(phone.destroy);
      desktop = await TestUser(
        'signature_images_desktop_$run',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: [blossomUrl],
        keyPair: phone.keyPair,
      ).create();
      addTearDown(desktop.destroy);
    });

    Future<void> delivered(TestUser user) async {
      while ((await user.client.blossomUploadQueue.listAll()).any(
        (u) => u.status != BlobUploadStatus.delivered,
      )) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<int> statusOf(String key) async =>
        (await http.get(Uri.parse('$blossomUrl/$key'))).statusCode;

    test('an image added on one device is read on another', () async {
      final key = await phone.client.addSignatureImage(
        png,
        mimeType: 'image/png',
        dim: '20x15',
      );
      await waitForBroadcasts(phone.client.broadcastQueue);
      await delivered(phone);

      final image = phone.client
          .cachedPrivateSettings()!
          .signatureImages![key]!;
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(image.mimeType, 'image/png');
      expect(image.dim, '20x15');
      expect(image.size, png.length + 16);

      await desktop.client.fetchPrivateSettings();
      expect(await desktop.client.getSignatureImage(key), png);
      expect(await desktop.client.getSignatureImage('0' * 64), isNull);
    });

    test('a blob that does not match its key is refused', () async {
      final key = await phone.client.addSignatureImage(
        png,
        mimeType: 'image/png',
      );
      await waitForBroadcasts(phone.client.broadcastQueue);
      await desktop.client.fetchPrivateSettings();
      await desktop.blossomCache.put(Uint8List(316), sha256: key);

      expect(
        () => desktop.client.getSignatureImage(key),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('inlines the images of a signature as cid parts', () async {
      final key = await phone.client.addSignatureImage(
        png,
        mimeType: 'image/png',
      );
      final signature = await phone.client.createSignature(
        'Full',
        html: '<p>Alice</p><img alt="logo" src="$key"><img src="other.png">',
      );

      final inline = await phone.client.inlineSignature(signature);

      expect(
        inline.html,
        '<p>Alice</p><img alt="logo" src="cid:$key@nostr-mail">'
        '<img src="other.png">',
      );
      expect(inline.images.single.bytes, png);

      final builder = MessageBuilder.prepareMultipartAlternativeMessage(
        plainText: 'Alice',
        htmlText: '<p>Hi</p>${inline.html}',
      );
      inline.addImagesTo(builder);
      final part = builder.buildMimeMessage().allPartsFlat.firstWhere(
        (p) => p.getHeaderValue('Content-ID') == '<$key@nostr-mail>',
      );
      expect(part.decodeContentBinary(), png);
      expect(part.mediaType.text, 'image/png');
    });

    test('removing an image drops its key and deletes its blob', () async {
      final key = await phone.client.addSignatureImage(
        png,
        mimeType: 'image/png',
      );
      await delivered(phone);
      expect(await statusOf(key), 200);

      await phone.client.removeSignatureImage(key);

      expect(phone.client.cachedPrivateSettings()!.signatureImages, isEmpty);
      while (await statusOf(key) != 404) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
  });
}
