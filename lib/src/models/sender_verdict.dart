/// What the user decided about a sender: [allow] routes its mail to the inbox,
/// [block] to spam. A sender with no verdict lands in requests.
enum SenderVerdict { allow, block }
