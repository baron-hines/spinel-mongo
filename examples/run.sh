#!/bin/sh
# Compile every examples/*.rb with Spinel, run it against a throwaway
# mongod, run it again under CRuby against the mongo gem, and diff the
# two outputs. A match means the example is the gem's API as well as
# this driver's.
#
# Usage: sh examples/run.sh          (from the repo root)
# Needs: spinel and spin, ruby with the mongo gem, and mongod on PATH.
# The mongod listens on $EXAMPLES_PORT and stops on exit.

EXAMPLES_PORT=${EXAMPLES_PORT:-27230}
OUTDIR=build/examples
export MONGODB_URI="mongodb://127.0.0.1:$EXAMPLES_PORT/examples"

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR/db"
mongod --port "$EXAMPLES_PORT" --bind_ip 127.0.0.1 --dbpath "$OUTDIR/db" \
  --wiredTigerCacheSizeGB 0.25 --logpath "$OUTDIR/mongod.log" > /dev/null 2>&1 &
mongod_pid=$!
trap 'kill $mongod_pid 2> /dev/null; wait $mongod_pid 2> /dev/null' EXIT

tries=0
until ruby -rsocket -e "TCPSocket.new('127.0.0.1', $EXAMPLES_PORT).close" 2> /dev/null; do
  tries=$((tries + 1))
  if [ $tries -gt 100 ] || ! kill -0 $mongod_pid 2> /dev/null; then
    echo "examples: mongod did not come up on $EXAMPLES_PORT (see $OUTDIR/mongod.log)" >&2
    exit 2
  fi
  sleep 0.1
done

flags=$(spin flags) || exit 2
fails=0
ran=0
for src in examples/*.rb; do
  name=$(basename "$src" .rb)
  ran=$((ran + 1))
  # shellcheck disable=SC2086
  if ! spinel $flags -I . "$src" -o "$OUTDIR/$name" > "$OUTDIR/$name.compile" 2>&1; then
    echo "FAIL $name: doesn't compile (see $OUTDIR/$name.compile)"
    fails=$((fails + 1))
    continue
  fi
  "$OUTDIR/$name" > "$OUTDIR/$name.out" 2>&1
  status=$?
  # The gem logs every command at debug level; keep warnings only.
  ruby -rmongo -e 'Mongo::Logger.logger.level = Logger::WARN; load ARGV.shift' "$src" > "$OUTDIR/$name.gem.out" 2>&1
  gem_status=$?
  if [ $status -ne 0 ] || [ $gem_status -ne 0 ]; then
    echo "FAIL $name: exit $status compiled, $gem_status under the gem (see $OUTDIR/$name.out, $name.gem.out)"
    fails=$((fails + 1))
  elif diff -u "$OUTDIR/$name.gem.out" "$OUTDIR/$name.out" > "$OUTDIR/$name.diff" 2>&1; then
    echo "ok   $name"
    rm -f "$OUTDIR/$name.diff"
  else
    echo "FAIL $name: output differs from the gem's (see $OUTDIR/$name.diff)"
    fails=$((fails + 1))
  fi
done

echo "$((ran - fails))/$ran examples run compiled and match the gem"
[ $fails -eq 0 ]
