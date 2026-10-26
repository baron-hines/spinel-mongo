#!/bin/sh
# Oracle harness: replay every flow that has a twin in oracle/ through
# the real gems (bson for the BSON flows, mongo for the wire and live
# ones) and diff its output against the flow's committed snapshot,
# test/<flow>_test.rb.expected. spin test checks the same snapshot
# against spinel-mongo compiled by Spinel, so a match here means the
# gems print the same as spinel-mongo from the same flow.
#
# Usage: sh oracle/run.sh            (from the repo root)
# Needs: ruby with the bson and mongo gems, and mongod on PATH. It
# starts its own mongod on $ORACLE_PORT with a throwaway --dbpath and
# stops it on exit. auth_live starts another, with --auth, on the port
# after it.

ORACLE_PORT=${ORACLE_PORT:-27217}
OUTDIR=build/oracle
FLOWS="bson_encode bson_decode bson_malformed wire_msg connection_live auth_live crud_live cursors_live bulk_live uri"

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR/db"
mongod --port "$ORACLE_PORT" --bind_ip 127.0.0.1 --dbpath "$OUTDIR/db" \
  --wiredTigerCacheSizeGB 0.25 --setParameter enableTestCommands=1 \
  --logpath "$OUTDIR/mongod.log" \
  --pidfilepath "$OUTDIR/mongod.pid" > /dev/null 2>&1 &
mongod_pid=$!
trap 'kill $mongod_pid 2> /dev/null; wait $mongod_pid 2> /dev/null' EXIT

tries=0
until ruby -rsocket -e "TCPSocket.new('127.0.0.1', $ORACLE_PORT).close" 2> /dev/null; do
  tries=$((tries + 1))
  if [ $tries -gt 100 ] || ! kill -0 $mongod_pid 2> /dev/null; then
    echo "oracle: mongod did not come up on $ORACLE_PORT (see $OUTDIR/mongod.log)" >&2
    exit 2
  fi
  sleep 0.1
done

fails=0
ran=0
for flow in $FLOWS; do
  ruby "oracle/$flow.rb" "$ORACLE_PORT" > "$OUTDIR/$flow.out" 2>&1
  ran=$((ran + 1))
  if diff -u "test/${flow}_test.rb.expected" "$OUTDIR/$flow.out" > "$OUTDIR/$flow.diff" 2>&1; then
    echo "ok   $flow"
    rm -f "$OUTDIR/$flow.diff"
  else
    echo "FAIL $flow (see $OUTDIR/$flow.diff)"
    fails=$((fails + 1))
  fi
done

echo "$((ran - fails))/$ran flows match the gems"
[ $fails -eq 0 ]
