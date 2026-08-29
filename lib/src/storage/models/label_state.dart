import 'email_record.dart';

/// The denormalized shape a set of NIP-32 labels gives an email.
///
/// The label store is the source of truth; this is what gets folded into an
/// [EmailRecord] so queries never need a join.
class LabelState {
  final String folder;
  final bool isRead;
  final bool isStarred;

  /// Labels that map to no dedicated column (custom tags).
  final List<String> labels;

  const LabelState({
    required this.folder,
    this.isRead = false,
    this.isStarred = false,
    this.labels = const [],
  });

  /// Fold [labels] into columns, falling back to [defaultFolder] when no
  /// `folder:` label is present.
  factory LabelState.fromLabels(
    Iterable<String> labels, {
    required String defaultFolder,
  }) {
    var folder = defaultFolder;
    var isRead = false;
    var isStarred = false;
    final others = <String>[];

    for (final label in labels) {
      if (label.startsWith('folder:')) {
        folder = label.substring(7);
      } else if (label == 'state:read') {
        isRead = true;
      } else if (label == 'flag:starred') {
        isStarred = true;
      } else if (!others.contains(label)) {
        others.add(label);
      }
    }

    return LabelState(
      folder: folder,
      isRead: isRead,
      isStarred: isStarred,
      labels: others,
    );
  }

  /// The state already denormalized onto [email].
  factory LabelState.of(EmailRecord email) => LabelState(
    folder: email.folder,
    isRead: email.isRead,
    isStarred: email.isStarred,
    labels: email.labels,
  );
}
