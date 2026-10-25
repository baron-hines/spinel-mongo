# mongo (spinel-mongo)

A pure Spinel-Ruby MongoDB driver, for programs compiled by
[Spinel](https://github.com/matz/spinel). It is a subset-compatible port
of the [`mongo`](https://rubygems.org/gems/mongo) gem: the package is
`mongo`, a program says `require "mongo"`, and the classes, methods and
errors it has are the gem's, so the same code runs under CRuby against
the real gem.

It is built like its siblings
[spinel-pg](https://github.com/rubys/spinel-pg) and
[spinel-redis](https://github.com/rubys/spinel-redis): BSON and the
`OP_MSG` wire protocol as pure functions, an incremental frame parser, a
client core over an injected transport (so the same tests run under CRuby
and compiled), and a thin transport over Spinel's `sp_net` sockets.

**Status: not usable yet.** BSON, the wire layer, the connection and
SCRAM authentication are in. The client and collection API arrive before
v0.1.0.

## Planned

v0.1.0, one server:

```ruby
require "mongo"

client = Mongo::Client.new("mongodb://app:secret@127.0.0.1:27017/railyard")
locos = client[:locomotives]
id = locos.insert_one({ "name" => "Big Boy", "wheels" => 24 }).inserted_id
locos.find({ "wheels" => { "$gt" => 12 } }).sort({ "wheels" => -1 }).limit(5).each do |doc|
  puts doc["name"]
end
locos.update_one({ "_id" => id }, { "$set" => { "retired" => true } })
locos.count_documents({ "retired" => true })   # => 1
```

- BSON: double, string, document, array, binary, ObjectId, boolean, UTC
  datetime, null, int32, int64, byte-identical to the bson gem.
- `OP_MSG`, the `hello` handshake, SCRAM-SHA-256 and SCRAM-SHA-1.
- `insert_one`/`insert_many`, `find` with `sort`/`limit`/`skip`/
  `projection`/`batch_size` and cursors, `update_one`/`update_many`,
  `replace_one`, `delete_one`/`delete_many`, `count_documents`,
  `estimated_document_count`, `distinct`, `drop`, `Database#command`.
- The gem's error classes, with the server's code and code name.

v0.2.0: TLS through Spinel's bundled `openssl` package (behind
`require "mongo/tls"`, so programs without TLS don't link libssl), and
seed lists of several hosts.

Not planned: sessions and transactions, change streams, GridFS, general
aggregation, and more. The full list is in
[UNPLANNED_FEATURES.md](UNPLANNED_FEATURES.md).

## Installing

Once a release is tagged, depend on it by tag in `spin.toml`:

```toml
[dependencies]
mongo = { git = "https://github.com/baron-hines/spinel-mongo", ref = "v0.1.0" }
```

Versions follow SemVer, 0.x until the API settles. Each release is a
`vX.Y.Z` tag on `main` with a GitHub release, and `CHANGELOG.md` says what
changed.

## Tests

```sh
spin test        # every test, compiled; some under CRuby too
sh oracle/run.sh # every flow with a twin, through the real gems
```

Tests with no committed `.expected` snapshot run compiled and under CRuby,
and the two outputs must be identical. Tests with a snapshot run compiled
and are diffed against it; `spin test --regen` takes snapshots from
CRuby. Live tests can't run under CRuby, since the transport binds
Spinel's sockets, so their snapshots come from the compiled run and the
oracle checks them. They need `mongod` on PATH.

The oracle checks the snapshots against the reference implementations.
A flow `test/<flow>_test.rb` with a snapshot has a twin,
`oracle/<flow>.rb`, that does the same through the `bson` gem (5.2.0) or
the `mongo` gem (2.26.0), and `oracle/run.sh` diffs each twin's output
against `test/<flow>_test.rb.expected`. So the BSON snapshots are bytes
and values the gem produces too. Live commands aren't compared byte for
byte, since the gem adds a session id that this driver doesn't send.

| Flow | Checks |
|---|---|
| `bson_encode` | 14 documents (commands, replies, every type and number edge) encode to the gem's bytes |
| `bson_decode` | The same bytes decode to the gem's values and classes, and Symbol keys read a `BSON::Document` |
| `bson_malformed` | 19 kinds of malformed input raise the gem's error classes, never read past the end |
| `wire_msg` | 8 `OP_MSG` requests, with and without a kind 1 section, match the bytes of the gem's `Mongo::Protocol::Msg` |
| `connection_live` | Against a real `mongod`: the handshake's limits, `ping`, an unknown command, a duplicate key, a bulk write with two, a read back, a command past `socket_timeout`, a refused connect, each raising the gem's class and message |
| `auth_live` | Against a `mongod` started with `--auth`: SCRAM-SHA-256 and SCRAM-SHA-1, chosen and negotiated, a wrong password, the wrong `authSource`, SCRAM-SHA-256 for a user without it, a command before any login and one outside the user's role, each with the gem's class and message |
| `crud_live` | Twin and snapshot only: `test/crud_live_test.rb` arrives with the collection API and must print the same lines |

`test/bson_values_test.rb` is dual-runtime: ObjectId generation, the
value classes, Document, number and string round trips, and the left-out
types. So is `test/wire_parser_test.rb`: the frame parser over a scripted
byte stream, with replies split at every awkward boundary, 500 in one
read, and 15 kinds of malformed reply. And `test/connection_test.rb`: the
connection over a scripted transport, with the handshake, each kind of
failed reply and each way a connection breaks. And `test/scram_test.rb`:
SHA-1, SHA-256, HMAC and PBKDF2 against published vectors, the whole
exchanges from RFC 7677, RFC 5802 and MongoDB's auth spec, each check on
the server's messages, and logins against a scripted server that does
the server side of SCRAM.

`test/timeouts_live_test.rb` checks that `connect_timeout` and
`socket_timeout` give up within a second of their setting, against
listeners that never accept. It has a snapshot but no twin: the gem
raises the same `Mongo::Error::NoServerAvailable`, but only after its
server selection loop.

Live tests start their own `mongod` (with test commands on, for
`sleep`) on a private port with a throwaway `--dbpath` under
`build/live/`, and stop it when they finish.

CI builds Spinel at a pinned commit on every pull request, and Spinel's
`master` once a week.

## Exclusion ledger

What the gem has and this driver doesn't, as it lands. What the gems
support that this driver has no plan to add, and where it differs from
them on purpose, is in [UNPLANNED_FEATURES.md](UNPLANNED_FEATURES.md).

**BSON**

- Decoding the types below raises `BSON::Error::UnsupportedType`, and
  they have no Ruby classes to encode from: Decimal128 (`BSON::Decimal128`,
  and so Mongoid's `BigDecimal` fields), regular expressions
  (`BSON::Regexp::Raw`), timestamps (`BSON::Timestamp`), JavaScript with or
  without scope, MinKey and MaxKey, DBPointer, undefined and the BSON
  symbol type. A Symbol value is written as a string, as the gem writes
  it by default.
- No `to_bson`, `from_bson`, `BSON::ByteBuffer` or extended JSON.
  Encode with `BSON.encode(hash)` and decode with `BSON.decode(bytes)` or
  `BSON::Reader.new(bytes, pos).document`.
- Any NaN is written as `000000000000f87f`, the bytes the gem writes for
  `Float::NAN`. The gem writes a NaN with another payload as it is.
- An Integer outside int64 raises `RangeError`, as in the gem. On Spinel
  one only gets there under `--int-overflow=promote`; by default the
  arithmetic that would make it raises first.
- `BSON::ObjectId` has no `from_time`, `to_bson` or `as_json`.
  `BSON::Document` reads Symbol keys through `[]`, `[]=`, `key?`, `fetch`,
  `delete` and `dig`, but doesn't convert nested Hashes on assignment, as
  the gem's does.

**Wire protocol**

- `OP_MSG` only. A reply with any other op code raises
  `Mongo::Error::UnsupportedMessageType`, as the gem does for one it
  doesn't know.
- No compression, and no checksum on requests. A reply's checksum is
  skipped, not checked.
- No exhaust cursors: a reply with `moreToCome` set raises
  `Mongo::Error::ProtocolError`, since nothing asks for one.
- `Mongo::Error::ProtocolError` is this driver's own class, for a reply
  that breaks the framing (a length too small for the header, a section
  past the end, an unknown section kind or required flag). The gem has no
  class for these. The connection is closed after one.

**Connection**

- One connection, no pool and no monitoring. A refused or timed-out
  connect, or a handshake that fails, raises
  `Mongo::Error::NoServerAvailable` at once, where the gem keeps trying
  for `server_selection_timeout` (30 seconds by default). The message
  names the address and the cause, not a server selector.
- After a network error, a read past `socket_timeout`, or a reply the
  driver can't trust, the connection is closed and later commands on it
  raise `Mongo::Error::SocketError`. Nothing is retried, since a write may
  have reached the server.
- `Mongo::Error::OperationFailure` and `BulkWriteError` carry the gem's
  message, built from the reply the same way, without two additions: the
  note on where it happened (`" (on 127.0.0.1:27017, ...)"`) and the
  server's `errInfo` details (`" -- {...}"`). `OperationFailure` has
  `code`, `code_name`, `server_message` and `document`, but no error
  labels, write concern accessors or retryability predicates.
- The handshake offers no compression and sends no `env` or
  `backpressure` fields. Its `platform` names the runtime and the Ruby
  version Spinel implements (`"Spinel (Ruby 4.0.7), x86_64-linux"`), not
  Spinel's own version, which a program can't read. Servers older than
  MongoDB 6.0 are refused with `Mongo::Error::UnsupportedFeatures`.

**Authentication**

- SCRAM-SHA-256 and SCRAM-SHA-1 only: no X.509, LDAP (`PLAIN`), Kerberos,
  AWS or MONGODB-CR. The mechanism is chosen as the gem chooses it, from
  the handshake's `saslSupportedMechs`, unless one is asked for.
- SCRAM-SHA-256 passwords must be printable ASCII. SASLprep leaves those
  unchanged, and anything else would need its Unicode tables, so other
  passwords raise `ArgumentError` before anything is sent. SCRAM-SHA-1
  takes any password, since MongoDB hashes it with MD5 first.
- No speculative authentication: the first step goes in its own
  `saslStart` rather than inside `hello`, which costs one round trip per
  connection. No credential cache: each login runs PBKDF2 again (about
  40 ms compiled at the server's default 15,000 rounds).
- `Mongo::Auth::Unauthorized` carries the gem's message without its last
  part, `", used server: 127.0.0.1:27017 (STANDALONE)"`, and has `code`
  but no error labels. A connection whose login fails is closed.
- The hashes are Spinel's bundled `digest` package, which binds the
  runtime's own crypto: a program that authenticates links no libssl.
  HMAC and PBKDF2 are Ruby over it.

## Spinel notes

Spinel behaviors the code works around, with the issue where there is one.

- `Float::NAN` and `0.0 / 0.0` pack with the sign bit set on Spinel
  (`000000000000f8ff`), where CRuby packs `000000000000f87f`. The encoder
  writes CRuby's bytes for every NaN, so documents match the gem's on
  both runtimes.
- Building a String with `s = s + piece` copies it every time and is
  quadratic on Spinel (2.5 s for 1 MB in 100-byte pieces), so the encoder
  appends with `<<`.
- A method whose last expression is `buf << x` returns the buffer, and
  once a program does that, Spinel copies the buffer on every later
  append: 40,000 appends of 100 bytes took 22 s instead of 41 ms. The
  encoder keeps its buffer in an ivar and every method that appends ends
  in `nil`. Encoding a 1.2 MB document takes about 50 ms compiled.
- `is_a?` doesn't narrow a `rescue` variable: after
  `rescue Mongo::Error => e`, `e.code` inside `if e.is_a?(Mongo::Error::OperationFailure)`
  raises `NoMethodError` compiled. Rescue the subclass itself, or pass
  `e` to a method and narrow there.

## License

MIT. See [LICENSE](LICENSE).
