# Fix flaky image_store_io_test "without picker copies everything is copied"

## what
`test/attachments/image_store_io_test.dart` "attachFile without picker copies
everything is copied" fails about 1 run in 4 under parallel load with
`PathNotFoundException: Cannot retrieve length of file` from
`ImageCacheStore._run` (`lib/images/image_cache_store.dart:135`). The test
returns while `IoImageStore.attachFile` still has its fire-and-forget
`unawaited(_sync(const {}))` running; teardown deletes the temp root and the
upload pass calls `file.length()` on a file that `existsSync()` just saw.
Predates the AccountManager branch (no file in lib/images, lib/attachments or
test/attachments was touched). Seen once as 591/592 and once with
`--reporter expanded` at 635/636.

## done
`for i in $(seq 20); do flutter test test/attachments/image_store_io_test.dart --concurrency=4 || exit 1; done`
exits 0, and the production path tolerates a file vanishing mid-pass (skip it
instead of throwing).

## verify
Same loop on this repo; plus the full suite ends with "All tests passed!".

## read first
- lib/attachments/image_store_io.dart (`attachFile`, `_sync`)
- lib/images/image_cache_store.dart (`_run`)

REMOVE ME AFTER FINISH
