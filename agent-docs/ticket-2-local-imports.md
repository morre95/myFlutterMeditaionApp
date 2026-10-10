# Ticket #2: durable local imports

Implemented on `integration/meditation-local-imports`; ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/2.

`AppDependencies` shares `LocalAudioLibrary` and `ManagedLocalAudioPicker` between
Library and Music. The low-level picker still selects read-only original paths;
the managed picker copies selections before returning playable sources.

Each sound has a random `import:` identity, its original display name, an
app-owned audio path, and `storedSize`. Audio and JSON metadata are flushed in a
hidden staging directory before rename publishes them. Failed/canceled batches
roll back their own copies without changing earlier imports or originals.
Catalog loading rebuilds locators from its current directory and excludes
missing, truncated, or malformed entries. Existing playlist JSON and original
source references remain supported; no migration occurs.

The user approved tests at the public import/catalog API with real temporary
files and reconstructed persistence, plus Library/Music screen actions using a
fake native player. Full suite: 143 passed; static analysis: no issues. Physical
Android decoding was outside this ticket's verification; ticket #11 retains
device acceptance.

Widget tests that combine real file I/O and screen actions run the scenario
inside `tester.runAsync`. Waiting there for an operation started in the fake
async zone can hang. Child-agent escalated calls also stalled in this session;
the parent executed SDK and Git commands directly.

Next frontier after merging #2: #3 (timed local meditation) and #6 (pCloud
downloads). This run intentionally implements only #2.
