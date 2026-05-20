# TODO

## Local-First Architecture

- [ ] Save labels locally BEFORE broadcasting to relays
- [ ] Mark labels as "pending sync" when broadcast fails
- [ ] Handle offline mode gracefully

## Labels

- [ ] `syncLabels`: clean up stale local labels (deleted on remote)
- [ ] Add pagination to `getTrashedEmails()` / `getStarredEmails()`
- [ ] Add `getArchivedEmails()`, `getSpamEmails()`
- [ ] Support custom folders (`folder:<custom>`)
- [ ] Add generic `moveToFolder(emailId, folder)` method

## Performance

- [ ] Cache write relays (avoid re-fetching on every operation)
- [ ] Batch label operations (add multiple labels at once)

## Tests

- [ ] Integration tests with mock NDK for `addLabel` / `removeLabel`
- [ ] Tests for `syncLabels`
- [ ] Offline behavior tests

- [ ] rewrite the tests with the mock relays and blossoms
- [ ] rethink the local database
