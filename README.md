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

**Status: not usable yet.** This is the package skeleton. Nothing below
the version constant exists until v0.1.0.

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
spin test    # dual-runtime lanes also run under CRuby and must match
```

Tests with no committed `.expected` snapshot run compiled and under CRuby,
and the two outputs must be identical. Live tests (from v0.1.0) start
their own `mongod` on private ports and diff a committed snapshot; they
need `mongod` on PATH. An oracle will replay every live flow through the
real `mongo` gem.

CI builds Spinel at a pinned commit on every pull request, and Spinel's
`master` once a week.

## Exclusion ledger

What the gem has and this driver doesn't, as it lands. Empty until there
is a driver to compare.

## Spinel notes

Spinel behaviors the code works around, with the issue where there is one.
Empty so far.

## License

MIT. See [LICENSE](LICENSE).
