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

The driver is still being built. Where an entry describes how the driver
behaves in a part that hasn't landed yet (TLS, seed lists), it describes
the design that part is being built to.

## Sessions and transactions

- **Sessions.**
  - **Explicit sessions.** The gem's `Client#start_session` returns a
    `Mongo::Session` that a program passes to operations with
    `session: s`, to group them on the server. This driver has no
    `Mongo::Session` and no `session:` option.
  - **Implicit sessions.** The gem attaches a session id (`lsid`) to every
    command, even when the program never asks for a session. This driver
    sends none. A server accepts commands without one, so results are the
    same; only the command documents differ by that one field.
  - **Causal consistency.** With sessions, the gem can guarantee that a
    read sees the program's own earlier writes, even on a secondary
    (`causal_consistency: true`). This driver reads and writes only on the
    primary, which gives that ordering anyway for one connection, but it
    has no option for it.

- **Multi-document transactions.**
  - **The transaction API.** The gem's `Session#with_transaction`, or
    `start_transaction`, `commit_transaction` and `abort_transaction`, run
    several writes across documents and collections as one unit that
    commits or rolls back together. This driver has none of them, since
    transactions need sessions. Each write here is atomic for the single
    document it changes, as on any MongoDB server, and no more.
  - **Transaction options.** The read concern, write concern and read
    preference a transaction takes, and the commit retry logic, go with
    the API above.

- **Retries.**
  - **Retryable writes.** The gem retries a write once after a network
    error or a primary change (`retry_writes: true`, the default), using
    the session's transaction number so the server applies it only once.
    This driver doesn't retry. After a network error it drops the
    connection, raises, and opens a new connection for the next command. A
    write may have reached the server before the connection failed, so the
    caller decides whether to repeat it.
  - **Retryable reads.** The gem also retries a read once (`retry_reads:
    true`). This driver doesn't; the read raises, and the caller can simply
    run it again.

## Operations

- **Change streams.**
  - **`watch`.** The gem's `Client#watch`, `Database#watch` and
    `Collection#watch` open a change stream: a cursor that yields an event
    for each insert, update, replace and delete as it happens, and can
    resume after a disconnect from a resume token. This driver has no
    `watch` and no change stream class. A program that needs to react to
    changes has to poll.

- **GridFS.**
  - **`Database#fs` and `Mongo::Grid::FSBucket`.** GridFS stores files
    larger than a document's 16 MiB limit by splitting them into chunks
    across two collections (`fs.files` and `fs.chunks`), with upload and
    download streams. This driver has neither the bucket class nor the
    streams. The two collections are ordinary collections, so a program
    could read or write them by hand, but nothing here helps.

- **Aggregation.**
  - **`Collection#aggregate` and `View#aggregate`.** The gem runs any
    aggregation pipeline (`$match`, `$group`, `$lookup`, `$unwind`,
    `$project` and the rest) and returns its results as a cursor. This
    driver has no general aggregation method.
  - **What does use `aggregate`.** `count_documents` sends the same fixed
    pipeline the gem sends (`$match`, then `$group` with `$sum`, plus
    `$skip` and `$limit` when given), so its counts match the gem's.
    `distinct` is its own command, not a pipeline.
  - **`map_reduce`.** The gem's `View#map_reduce` runs JavaScript map and
    reduce functions on the server. The server has deprecated map-reduce
    in favor of pipelines, and this driver doesn't have it.
  - **By hand.** `Database#command` sends any command document, so a
    program can send an `aggregate` command itself. It then reads the first
    batch from the reply and has to send any `getMore` itself too.

- **Read preferences, read concerns and write concerns.**
  - **Read preference.** The gem's `read:` option (`mode: :secondary`,
    `:secondary_preferred`, `:nearest` and so on, with tag sets and
    `max_staleness`) sends reads to replica set secondaries. This driver
    sends every command, reads included, to the primary.
  - **Read concern.** The gem's `read_concern:` (`local`, `majority`,
    `linearizable`, `snapshot`) controls how durable the data a read
    returns must be. This driver sends no read concern, so the server's
    default applies.
  - **Write concern.** The gem's `write_concern:` (`w`, `j`, `wtimeout`)
    says how many members must acknowledge a write and whether it must be
    journaled first. This driver sends no write concern, so the server's
    default applies (majority on replica sets since MongoDB 5.0). It still
    raises when the server reports a write concern error.

- **Other `find` options.** `find` here takes `sort`, `limit`, `skip`,
  `projection` and `batch_size`. The gem's other options are not there:
  - **`collation`.** Language-aware string comparison, such as
    case-insensitive matching and sorting.
  - **`hint`.** Forces the server to use a particular index.
  - **`comment`.** A string the server writes to its logs and profiler
    with the query, to find it later.
  - **`max_time_ms`.** A server-side time limit after which the server
    aborts the query.
  - **`allow_disk_use`.** Lets a large sort spill to disk instead of
    failing at the server's memory limit.
  - **Tailable cursors.** `cursor_type: :tailable` or `:tailable_await`
    keeps a cursor on a capped collection open and yields documents as
    they are inserted.

## Connections and topology

- **Server monitoring.**
  - **Monitoring threads.** The gem keeps one background thread per server
    that sends `hello` every 10 seconds (`heartbeat_frequency`) and tracks
    which member is primary, what each server's round-trip time is, and
    which servers are down. This driver has no background threads. It
    learns about the server only from the connection it is using.
  - **Server selection.** Before each operation the gem picks a suitable
    server, and when none is reachable it keeps trying for
    `server_selection_timeout` (30 seconds by default) before raising
    `Mongo::Error::NoServerAvailable`. This driver raises the same error at
    once, when its connection attempt fails. Programs that rely on the
    gem waiting out a short failover have to retry themselves.
  - **SDAM events.** The gem publishes server and topology change events
    to subscribers. This driver has no topology to report on (see
    [Command and server events](#monitoring-and-logging)).

- **Load-balanced mode.**
  - **`load_balanced: true`.** The gem can connect through a load balancer
    in front of a sharded cluster, as MongoDB's serverless offerings did,
    pinning cursors and transactions to one connection. This driver has
    no such mode. It talks to one server, or (from v0.2.0) to the primary
    of a seed list.

- **UNIX domain sockets.**
  - **A socket path as the host.** The gem connects to
    `/tmp/mongodb-27017.sock`, given as is or percent-encoded in a URI.
    This driver reads such a URI as the gem does, but connects only over
    TCP, and raises `ArgumentError` for a socket path.

- **Compression.**
  - **`compressors`.** The gem can compress messages on the wire with
    zlib, snappy or zstd (`compressors: ["zstd"]`, or `compressors=` in the
    URI), which cuts bandwidth to a remote server. This driver offers no
    compressor in its handshake, so the server never sends compressed
    replies, and it sends none itself.

- **Old servers and legacy opcodes.**
  - **Servers before MongoDB 6.0.** The gem supports servers back to 3.6.
    This driver refuses a server whose `hello` reports a wire version
    below 17 (MongoDB 6.0), with an error saying so.
  - **`OP_QUERY` and other legacy opcodes.** Older servers took commands as
    `OP_QUERY` messages, and the gem still uses one for the first handshake
    when it must. This driver sends everything, the handshake included, as
    `OP_MSG`, which every server from 3.6 on accepts.

- **OCSP.**
  - **Certificate revocation.** With TLS, the gem can check that the
    server's certificate hasn't been revoked, through OCSP stapling or an
    OCSP request (`tlsDisableOCSPEndpointCheck` and related options). This
    driver's TLS verifies the certificate chain against the trust store or
    `tlsCAFile` and checks the hostname, but makes no revocation check.

## Authentication

- **Mechanisms.** SCRAM-SHA-256 and SCRAM-SHA-1 are the only mechanisms.
  The gem's others are not here:
  - **X.509** (`MONGODB-X509`). Logs in with the client's TLS certificate
    instead of a password.
  - **LDAP** (`PLAIN`). Sends a username and password for the server to
    check against an LDAP directory (MongoDB Enterprise and Atlas).
  - **Kerberos** (`GSSAPI`). Logs in with a Kerberos ticket (MongoDB
    Enterprise).
  - **AWS** (`MONGODB-AWS`). Logs in with AWS IAM credentials, from the
    environment, an EC2 or ECS role, or explicit keys (Atlas).
  - **OIDC** (`MONGODB-OIDC`). Logs in with a token from an OpenID Connect
    identity provider, such as Azure, GCP or a custom callback.

- **Non-ASCII passwords on SCRAM-SHA-256.**
  - **SASLprep.** SCRAM-SHA-256 requires the password to be prepared with
    SASLprep (RFC 4013) before hashing, which maps some characters and
    applies Unicode NFKC normalization. The gem does this for any
    password. This driver doesn't have Unicode normalization tables, so it
    raises `ArgumentError` for a password with characters outside
    printable ASCII when SCRAM-SHA-256 is used.
  - **What works.** Printable ASCII passwords, which SASLprep leaves
    unchanged, work with SCRAM-SHA-256. SCRAM-SHA-1 doesn't use SASLprep,
    so any password works with it.

## Security

- **Client-side field level encryption and Queryable Encryption.**
  - **Automatic encryption.** The gem's `auto_encryption_options` encrypts
    chosen fields in the client before they are sent and decrypts them on
    the way back, so the server never sees them in plaintext. This needs
    the `libmongocrypt` library and a key management service. This driver
    has no such option.
  - **Explicit encryption.** The gem's `Mongo::ClientEncryption` creates
    data keys and encrypts or decrypts single values by hand. This driver
    doesn't have it either.

## Monitoring and logging

- **Command and server events.**
  - **`Mongo::Monitoring` and `Client#subscribe`.** The gem publishes an
    event when each command starts, succeeds or fails (with its duration),
    plus events for connection pools, servers and the topology. Tools such
    as APM agents and query loggers subscribe to them. This driver
    publishes no events and has no subscribe method.

- **Logging.**
  - **`Mongo::Logger`.** The gem logs commands and connection activity
    through a configurable Ruby `Logger` (Rails' logger, under Mongoid).
    This driver writes no logs of its own; errors reach the program as
    exceptions.

## BSON

- **Types.** These BSON types have no Ruby class here. Decoding a
  document that holds one raises `BSON::Error::UnsupportedType` naming
  the type byte, and there is nothing to encode one from:
  - **JavaScript code, with or without scope** (`BSON::Code`,
    `BSON::CodeWithScope`). Server-side JavaScript functions stored as
    values. The server has deprecated the scoped form.
  - **MinKey and MaxKey** (`BSON::MinKey`, `BSON::MaxKey`). Values that
    compare lower and higher than every other value, used mostly in
    sharding ranges.
  - **DBPointer** (`BSON::DbPointer`). A deprecated reference to a
    document in another collection. Today's equivalent is a DBRef, which
    is an ordinary embedded document and decodes as one here.
  - **Undefined** (`BSON::Undefined`). A deprecated value distinct from
    null.
  - **The symbol type** (`BSON::Symbol::Raw`). A deprecated string type. A
    Ruby Symbol value is written as a plain string, as the gem writes it
    by default, and decodes as a String.

- **Serialization API.**
  - **`to_bson` and `from_bson`.** The gem adds `to_bson` to Hash, Array,
    String, Integer and the other core classes, and `from_bson` to read
    them back from a buffer. This driver doesn't extend core classes.
    Encode a document with `BSON.encode(hash)`, and decode with
    `BSON.decode(bytes)` or `BSON::Reader.new(bytes, pos).document`.
  - **`BSON::ByteBuffer`.** The gem's read and write buffer for BSON bytes.
    This driver works on plain binary Strings instead.
  - **Registering custom types.** With `to_bson` and `bson_type`, the gem
    lets a program teach BSON to encode its own classes. This driver
    encodes only the classes it knows.

- **Extended JSON.**
  - **`as_extended_json` and `BSON::ExtJSON`.** Extended JSON is the JSON
    form of BSON that keeps types JSON lacks, such as
    `{"$oid": "…"}` for an ObjectId or `{"$date": …}` for a datetime, in
    canonical and relaxed modes. The gem writes and parses it. This driver
    does neither.
  - **`as_json` and `to_json` on the value classes.** Likewise not here, so
    `BSON::ObjectId#to_json` and friends aren't available. `to_s` gives an
    ObjectId's hex string.

- **`BSON::ObjectId`.**
  - **`from_time`.** The gem builds an ObjectId whose timestamp is a given
    time, which is handy for range queries on `_id` by creation time. Not
    here.
  - **`to_bson` and `as_json`.** See the two sections above.
  - **What is here.** `new`, `from_string`, `from_data`, `legal?`, `to_s`,
    `to_str`, `generation_time`, `==`, `eql?`, `hash`, `<=>` and `inspect`.

- **`BSON::Document`.**
  - **Symbol keys.** As in the gem, a decoded document reads and writes
    Symbol keys as their String names through `[]`, `[]=`, `key?`,
    `fetch`, `delete` and `dig`.
  - **Nested conversion.** The gem's `BSON::Document` turns a plain Hash
    stored into it into a `BSON::Document` too, so nested values answer
    Symbol keys as well. This one stores the Hash as given. Documents
    decoded from the server are `BSON::Document` at every level either
    way.

- **NaN payloads.**
  - **Canonical NaN.** A NaN has many bit patterns. The gem writes
    `Float::NAN` as `000000000000f87f`, and any other NaN with whatever
    bits it has. This driver writes every NaN as `000000000000f87f`,
    because Spinel's NaN has the sign bit set and would otherwise give
    different bytes from the same program under CRuby. A NaN's payload is
    lost on encoding; it is still a NaN.

## Planned, not here

These are missing today and have a plan, so they aren't listed above:

- TLS (behind `require "mongo/tls"`) and seed lists of several hosts, in
  v0.2.0. Seed lists bring `BSON::Timestamp` with them, since every reply
  from a replica set member carries timestamps (`operationTime` and
  `$clusterTime`). Until then, a document holding one raises
  `BSON::Error::UnsupportedType`, and so does `serverStatus` unless it is
  asked without its `storageEngine` and `wiredTiger` sections.
- Decimal128 and BSON regular expressions, `find_one_and_update` and the
  other `findAndModify` helpers, and `bulk_write`, once an application
  needs them.
- `createIndexes`, `listIndexes` and `dropIndexes`, and `mongodb+srv`
  URIs, in a later release.
- A connection pool, if measurement shows one connection per client under
  a Mutex isn't enough.
