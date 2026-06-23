import 'package:blossom_cache/blossom_cache.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';

void main() async {
  // Initialize Sembast database (use sembast_io for file-based storage)
  final db = await databaseFactoryMemory.openDatabase('nostr_mail.db');

  // Initialize NDK with your keys
  final ndk = Ndk(
    NdkConfig(
      bootstrapRelays: ['wss://relay.damus.io', 'wss://nos.lol'],
      eventVerifier: Bip340EventVerifier(),
      cache: MemCacheManager(),
      fetchedRangesEnabled: true,
    ),
  );

  final keyPair = Bip340.generatePrivateKey();
  ndk.accounts.loginPrivateKey(
    pubkey: keyPair.publicKey,
    privkey: keyPair.privateKey!,
  );

  // Local store for large-email blobs while they are uploading to Blossom.
  // On web use `idbFactoryBrowser`; on native use `idbFactorySembastIo` so
  // pending uploads survive restarts.
  final BlossomCache blossomCache = await IdbBlossomCache.open(
    factory: newIdbFactoryMemory(),
  );

  // Create the mail client (runs any pending schema migration first)
  final client = await NostrMailClient.create(
    ndk: ndk,
    db: db,
    blossomCache: blossomCache,
  );

  // Sync emails from relays
  await client.sync();

  // Get cached emails
  final emails = await client.getEmails(limit: 10);
  for (final email in emails) {
    print('From: ${email.mime.fromEmail}');
    print('Subject: ${email.mime.decodeSubject()}');
    print('---');
  }

  // Watch for all mail events in real-time
  client.watch().listen((event) {
    switch (event) {
      case EmailReceived():
        print(
          'New email from ${event.email.mime.fromEmail}: ${event.email.mime.decodeSubject()}',
        );
      case EmailDeleted():
        print('Email deleted: ${event.emailId}');
      case LabelAdded():
        print('Label added: ${event.label} to ${event.emailId}');
      case LabelRemoved():
        print('Label removed: ${event.label} from ${event.emailId}');
    }
  });

  // Or use convenience streams
  client.onEmail.listen((email) {
    print('New email: ${email.mime.decodeSubject()}');
  });

  client.onTrash.listen((event) {
    print('Trash event: $event');
  });

  // Send to a Nostr user you already have the pubkey for.
  await client.send(
    to: [NostrRecipient.fromPubkey('<recipient-hex-pubkey>')],
    subject: 'Hello from Nostr!',
    body: 'This is a test email sent via Nostr.',
  );

  // Resolve a raw address (npub / NIP-05) into a Recipient, then send. This
  // throws if a NIP-05 lookup fails, so a Nostr user is never misrouted to a
  // bridge.
  final alice = await resolveRecipient(to: 'alice@nostr.directory', ndk: ndk);
  await client.send(
    to: [alice],
    subject: 'Hello Alice!',
    body: 'Sending via your NIP-05 address.',
  );

  // Send to a legacy email, relayed through your own SMTP bridge.
  await client.send(
    from: MailAddress(
      null,
      '${Nip19.encodePubKey(keyPair.publicKey)}@bridge.example',
    ),
    to: [SmtpRecipient('bob@gmail.com')],
    subject: 'Hello from Nostr!',
    body: 'This email was sent via the Nostr bridge.',
  );
}
