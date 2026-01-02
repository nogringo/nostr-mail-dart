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
    ),
  );

  final keyPair = Bip340.generatePrivateKey();
  ndk.accounts.loginPrivateKey(
    pubkey: keyPair.publicKey,
    privkey: keyPair.privateKey!,
  );

  // Create the mail client
  final client = NostrMailClient(ndk: ndk, db: db);

  // Sync emails from relays
  await client.sync();

  // Get cached emails
  final emails = await client.getEmails(limit: 10);
  for (final email in emails) {
    print('From: ${email.from}');
    print('Subject: ${email.subject}');
    print('---');
  }

  // Watch for new emails in real-time
  client.watchInbox().listen((email) {
    print('New email from ${email.from}: ${email.subject}');
  });

  // Send to a Nostr user (npub)
  await client.send(
    to: 'npub1abc123...',
    subject: 'Hello from Nostr!',
    body: 'This is a test email sent via Nostr.',
  );

  // Send to a NIP-05 identifier
  await client.send(
    to: 'alice@nostr.directory',
    subject: 'Hello Alice!',
    body: 'Sending via your NIP-05 address.',
  );

  // Send to a legacy email (routed via bridge)
  await client.send(
    to: 'bob@gmail.com',
    subject: 'Hello from Nostr!',
    body: 'This email was sent via the Nostr bridge.',
  );
}
