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
