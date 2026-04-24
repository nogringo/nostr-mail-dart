import 'dart:async';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/client.dart';
import 'package:nostr_mail/src/models/email.dart';

import 'package:sembast/sembast_memory.dart';

class MockBridge {
  final String domain;
  List<String>? defaultDmRelays;
  List<String>? defaultBlossomServers;
  Map<String, String>? nip05Overrides;

  late KeyPair keyPair;
  late Ndk ndk;
  late Database db;
  late NostrMailClient client;

  final Map<String, List<MimeMessage>> mailboxes = {};
  StreamSubscription<Email>? _emailSubscription;

  MockBridge(
    this.domain, {
    this.defaultDmRelays,
    this.defaultBlossomServers,
    this.nip05Overrides,
  });

  /// Helper to get the expected NIP-05 identifier for this bridge
  String get nip05 => '_smtp@$domain';

  List<MimeMessage> getEmails(String address) => mailboxes[address] ?? [];

  Future<MockBridge> start() async {
    keyPair = Bip340.generatePrivateKey();
    ndk = Ndk(
      NdkConfig(
        eventVerifier: Bip340EventVerifier(),
        cache: MemCacheManager(),
        bootstrapRelays: defaultDmRelays ?? [],
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    db = await databaseFactoryMemory.openDatabase('bridge_$domain');

    client = NostrMailClient(
      ndk: ndk,
      db: db,
      defaultDmRelays: defaultDmRelays,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
    );

    _emailSubscription = client.onEmail.listen((email) async {
      final rumor = await client.getRumor(email.id);
      final rcptToTags = rumor?.getTags('rcpt-to') ?? [];

      final mime = email.mime;
      final mimeRecipients = [...?mime.to, ...?mime.cc, ...?mime.bcc];

      // Combine rcpt-to and MIME headers into a Set to avoid duplicates
      final allRecipients = <String>{};
      allRecipients.addAll(rcptToTags);
      allRecipients.addAll(mimeRecipients.map((addr) => addr.email));

      for (final address in allRecipients) {
        mailboxes.putIfAbsent(address, () => []).add(mime);
      }
    });

    return this;
  }

  Future<void> stop() async {
    await _emailSubscription?.cancel();
    await ndk.destroy();
    await db.close();
  }

  Future<void> receiveMailFromSmtp(
    MailAddress mailFrom,
    MimeMessage mime,
  ) async {
    await client.sendMime(mime, keepCopy: false, mailFrom: mailFrom.email);
  }
}
