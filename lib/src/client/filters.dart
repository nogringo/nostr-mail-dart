import 'package:ndk/ndk.dart';

import '../constants.dart';

/// Filter for incoming gift-wrap emails (kind 1059).
Filter emailFilter(String pubkey) =>
    Filter(kinds: [GiftWrap.kGiftWrapEventkind], pTags: [pubkey]);

/// Filter for public emails where the user is mentioned (kind 1301).
Filter publicEmailFilter(String pubkey) =>
    Filter(kinds: [emailKind], pTags: [pubkey]);

/// Filter for NIP-32 label additions (kind 1985, namespace "mail").
Filter labelFilter(String pubkey) =>
    Filter(kinds: [labelKind], authors: [pubkey])
      ..setTag('L', [labelNamespace]);

/// Unified deletion filter (kind 5) covering emails, labels and reposts.
Filter deletionFilter(String pubkey) =>
    Filter(kinds: [deletionRequestKind], authors: [pubkey])..setTag('k', [
      giftWrapKind.toString(),
      emailKind.toString(),
      labelKind.toString(),
      genericRepostKind.toString(),
    ]);

/// Filter for generic reposts (kind 16).
Filter repostFilter(String pubkey) =>
    Filter(kinds: [genericRepostKind], authors: [pubkey]);

/// Filter for encrypted private settings (kind 30078).
Filter settingsFilter(String pubkey) =>
    Filter(kinds: [appSettingsKind], authors: [pubkey])
      ..setTag('d', [privateSettingsDTag]);

/// Filter for metadata and relay lists
/// (kinds 0, 10002, 10050, 10063).
Filter metadataFilter(String pubkey) => Filter(
  kinds: [metadataKind, relayListKind, dmRelayListKind, blossomServerListKind],
  authors: [pubkey],
);

/// Every filter the sync engine fetches for [pubkey].
List<Filter> syncFilters(String pubkey) => [
  emailFilter(pubkey),
  deletionFilter(pubkey),
  publicEmailFilter(pubkey),
  labelFilter(pubkey),
  repostFilter(pubkey),
  settingsFilter(pubkey),
  metadataFilter(pubkey),
];
