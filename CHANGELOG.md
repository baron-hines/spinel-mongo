# Changelog

All notable changes to this package. Versions follow
[Semantic Versioning](https://semver.org/); `spin.toml`'s version moves
in the same pull request as the change.

## Unreleased

- The package skeleton: `spin.toml`, `Mongo::VERSION`, one dual-runtime
  test, and CI.
- The oracle harness, `oracle/run.sh`, with its first flow (`crud_live`).
- BSON: `BSON.encode` and `BSON.decode` for double, string, document,
  array, binary, ObjectId, boolean, UTC datetime, null, int32 and int64,
  byte-identical to the bson gem; `BSON::ObjectId`, `BSON::Int64`,
  `BSON::Binary`, `BSON::Document` and the gem's error classes.
- The wire layer: `Mongo::Wire.op_msg`, byte-identical to the gem's
  `OP_MSG` requests, and `Mongo::Wire::Parser`, which cuts replies out of
  a byte stream. `Mongo::Error` with `MaxMessageSize`,
  `UnsupportedMessageType` and `ProtocolError`.
- The connection: `Mongo::Transport` over Spinel's sockets with
  `connect_timeout` and `socket_timeout`, and `Mongo::Connection` with the
  `hello` handshake, `command`, `command_seq` and `write_seq`. The gem's
  `OperationFailure`, `BulkWriteError`, `NoServerAvailable`, `SocketError`,
  `SocketTimeoutError`, `UnexpectedResponse` and `UnsupportedFeatures`,
  with the gem's messages for failed replies.
- SCRAM-SHA-256 and SCRAM-SHA-1: `Mongo::Scram` over the bundled `digest`
  and `securerandom` packages, and `Connection#authenticate`, which picks
  the mechanism as the gem does. The gem's `Mongo::Auth::Unauthorized`,
  `InvalidNonce`, `InvalidSignature`, `InsufficientIterationCount`,
  `MissingScramServerSignature` and `InvalidServerAuthResponse`.
- The client and collection API: `Mongo::Client.new(["host:port"],
  options)` with `[]`, `database`, `use` and `close`; `Database#command`,
  `#[]` and `#collection_names`; `Collection#find`, `insert_one`,
  `insert_many` (batched by the server's limits), `update_one`,
  `update_many`, `replace_one`, `delete_one`, `delete_many`,
  `count_documents`, `estimated_document_count`, `distinct` and `drop`;
  `Collection::View` with `sort`, `limit`, `skip`, `projection`,
  `batch_size`, `each`, `first`, `to_a` and `count_documents`, over
  cursors that send `getMore` and close themselves with `killCursors`.
  The gem's result classes and `Mongo::Error::MaxBSONSize`.
- Connection strings: `Mongo::URI`, which reads `mongodb://` URIs as the
  gem does, and `Mongo::Client.new(uri, options)`, with the gem's
  `Mongo::Error::InvalidURI` and its checks on credentials.
- Threads and forks: threads share a client's connection a round trip at
  a time, a forked child opens its own, and a connection the server has
  closed since its last reply is replaced before it is used.
- Examples: `examples/quickstart.rb` and `examples/threads.rb`, which
  `examples/run.sh` compiles and runs in CI, checking each against the
  gem's output for the same program.
