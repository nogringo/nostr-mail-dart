import 'dart:async';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/src/client.dart';
import 'package:nostr_mail/src/models/email.dart';
import 'package:nostr_mail/src/models/recipient.dart';
import 'package:nostr_mail/src/utils/recipient_resolver.dart';

import 'package:sembast/sembast_memory.dart';

import '../helpers/test_blossom_cache.dart';

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

  /// Envelopes the bridge accepted for relay, in arrival order. Each entry is
  /// the SMTP envelope reconstructed from the rumor's `mail-from`/`rcpt-to`
  /// tags - what a real bridge would hand to the outbound MTA.
  final List<({String mailFrom, List<String> rcptTo})> receivedEnvelopes = [];

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
        fetchedRangesEnabled: true,
      ),
    );

    ndk.accounts.loginPrivateKey(
      pubkey: keyPair.publicKey,
      privkey: keyPair.privateKey!,
    );

    db = await databaseFactoryMemory.openDatabase('bridge_$domain');

    client = await NostrMailClient.create(
      ndk: ndk,
      db: db,
      blossomCache: await openTestBlossomCache('bridge_$domain'),
      defaultDmRelays: defaultDmRelays,
      defaultBlossomServers: defaultBlossomServers,
      nip05Overrides: nip05Overrides,
    );

    _emailSubscription = client.onEmail.listen((email) async {
      final rumor = await client.getRumor(email.id);
      final mailFrom = rumor?.getFirstTag('mail-from');
      final rcptTos = rumor?.getTags('rcpt-to') ?? [];

      // A real SMTP bridge routes on the envelope, not the MIME headers: it
      // relays to each `rcpt-to` and refuses anything missing an envelope
      // sender or recipient. Mirroring that here makes the test fail loudly
      // when the client omits the `mail-from`/`rcpt-to` tags.
      if (mailFrom == null || rcptTos.isEmpty) return;

      receivedEnvelopes.add((mailFrom: mailFrom, rcptTo: rcptTos));

      final mime = email.mime;
      for (final address in rcptTos) {
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
    Future<List<Recipient>> resolve(List<MailAddress>? addrs) async => [
      for (final a in addrs ?? const <MailAddress>[])
        await resolveRecipient(
          to: a.encode(),
          ndk: ndk,
          nip05Overrides: nip05Overrides,
        ),
    ];
    await client.sendMime(
      mime,
      to: await resolve(mime.to),
      cc: await resolve(mime.cc),
      bcc: await resolve(mime.bcc),
      keepCopy: false,
      mailFrom: mailFrom.email,
    );
  }
}
