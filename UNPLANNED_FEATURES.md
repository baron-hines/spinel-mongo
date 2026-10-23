# Unplanned features

What the [`mongo`](https://rubygems.org/gems/mongo) gem (2.26.0) and the
[`bson`](https://rubygems.org/gems/bson) gem (5.2.0) support that this
driver doesn't, with no current plan to add it. It also lists the places
where the driver behaves differently from the gems on purpose.

Nothing here is ruled out for good. If you need one of these, open an
issue and say what for; that is how an item moves into a release plan.

Gaps that do have a plan are not listed here. They are at the end, under
[Planned, not here](#planned-not-here). The README's
[exclusion ledger](README.md#exclusion-ledger) tracks what is missing
from the code as it stands today, planned or not.

## Sessions and transactions

- **Sessions.** No `Client#start_session`, no causal consistency, and no
  implicit sessions: commands carry no `lsid`, so they differ from the
  gem's by that one field.
- **Multi-document transactions.** No `Session#with_transaction`,
  `start_transaction`, `commit_transaction` or `abort_transaction`.
  Transactions need sessions.
- **Retryable writes and reads.** A command that fails on a network error
  is not retried. After the error the connection is dropped, and the next
  command opens a new one. A write may have reached the server, so the
  caller decides whether to repeat it.

## Operations

- **Change streams.** No `watch` on a client, database or collection.
- **GridFS.** No `Database#fs` or `Mongo::Grid::FSBucket`.
- **Aggregation.** No general pipelines through `Collection#aggregate` or
  `View#aggregate`, and no `map_reduce`. `count_documents` sends the
  gem's fixed `$match`/`$group` pipeline, and `distinct` is its own
  command. `Database#command` can still send any command by hand.
- **Read preferences, read concerns and write concerns.** Every command
  goes to the primary with the server's default read and write concern.
  There is no `read:` option (secondary reads), `read_concern:` or
  `write_concern:` (`w`, `j`, `wtimeout`).
- **Other `find` options.** Only `sort`, `limit`, `skip`, `projection` and
  `batch_size`. No `collation`, `hint`, `comment`, `max_time_ms`,
  `allow_disk_use`, or tailable cursors.

## Connections and topology

- **Server monitoring.** No monitoring threads or heartbeats, and no
  server selection loop. When no server can be reached,
  `Mongo::Error::NoServerAvailable` is raised at once, where the gem waits
  up to `server_selection_timeout` (30 seconds by default).
- **Load-balanced mode.** No `load_balanced: true`.
- **Compression.** No `compressors` (zlib, snappy, zstd). The handshake
  offers none, so the server sends none.
- **Old servers.** MongoDB 6.0 (wire version 17) and later only. No
  `OP_QUERY` and no legacy opcodes; everything goes over `OP_MSG`.
- **OCSP.** TLS certificates are verified against the trust store and the
  hostname, with no OCSP checks or stapling.

## Authentication

- **Mechanisms.** SCRAM-SHA-256 and SCRAM-SHA-1 only. No X.509, LDAP
  (`PLAIN`), Kerberos (`GSSAPI`), AWS (`MONGODB-AWS`) or OIDC.
- **Non-ASCII passwords on SCRAM-SHA-256.** These need SASLprep, which
  needs Unicode normalization. Such a password raises `ArgumentError`.
  Printable ASCII passwords, which SASLprep leaves unchanged, work.

## Security

- **Client-side field level encryption and Queryable Encryption.** No
  `auto_encryption_options` and no `Mongo::ClientEncryption`.

## Monitoring and logging

- **Command and server events.** No `Mongo::Monitoring` and no
  `Client#subscribe`.
- **Logging.** No `Mongo::Logger`; the driver writes no logs.

## BSON

- **Types.** JavaScript code (with or without scope), Timestamp, MinKey
  and MaxKey, DBPointer, undefined and the BSON symbol type. Decoding one
  raises `BSON::Error::UnsupportedType`, and there is no Ruby class to
  encode one from. A Ruby Symbol is written as a string, as the gem
  writes it by default.
- **Serialization API.** No `to_bson`, `from_bson`, `BSON::ByteBuffer`,
  or `to_bson` on core classes. Encode with `BSON.encode(hash)` and decode
  with `BSON.decode(bytes)` or `BSON::Reader.new(bytes, pos).document`.
- **Extended JSON.** No `as_extended_json`, `BSON::ExtJSON` or
  `as_json` on the value classes.
- **`BSON::ObjectId`.** No `from_time`, `to_bson` or `as_json`.
- **`BSON::Document`.** Symbol keys work through `[]`, `[]=`, `key?`,
  `fetch`, `delete` and `dig`, but nested Hashes are not converted to
  `BSON::Document` on assignment, as the gem's are.
- **NaN payloads.** Every NaN is written as `000000000000f87f`, the bytes
  the gem writes for `Float::NAN`. The gem writes a NaN with another
  payload as it is.

## Planned, not here

These are missing today and have a plan, so they aren't listed above:

- TLS (behind `require "mongo/tls"`) and seed lists of several hosts, in
  v0.2.0.
- Decimal128 and BSON regular expressions, `find_one_and_update` and the
  other `findAndModify` helpers, and `bulk_write`, once an application
  needs them.
- `createIndexes`, `listIndexes` and `dropIndexes`, and `mongodb+srv`
  URIs, in a later release.
- A connection pool, if measurement shows one connection per client under
  a Mutex isn't enough.
