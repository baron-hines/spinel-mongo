# Live: connect_timeout and socket_timeout against listeners that never
# accept. One has a full accept queue, so the kernel drops new SYNs and
# a connect hangs as one to a dead host does. The other has room in its
# queue, so the connect completes and the handshake's hello is never
# answered. Both raise NoServerAvailable within a second of the setting,
# as the gem's server selection does. Spinel-only (the committed
# .expected keeps spin test from running it under CRuby). It has no
# oracle twin: the gem raises the same error but only after its server
# selection loop, 2.5 seconds here with every timeout at 1, and this
# test is about when the driver gives up. Needs no mongod.
require "mongo"

module StuckListener
  ffi_func :sp_net_listen_host,          [:str, :int, :int],    :int
  ffi_func :sp_net_local_port,           [:int],                :int
  ffi_func :sp_net_connect_timeout,      [:str, :int, :double], :int
  ffi_func :sp_net_take_connect_timeout, [],                    :int
  ffi_func :sp_net_close,                [:int],                :int
end

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

full = StuckListener.sp_net_listen_host("127.0.0.1", 0, 1)
full_port = StuckListener.sp_net_local_port(full)
held = []
fd = 0
tries = 0
while fd >= 0 && tries < 8
  fd = StuckListener.sp_net_connect_timeout("127.0.0.1", full_port, 0.3)
  held.push(fd) if fd >= 0
  tries += 1
end
StuckListener.sp_net_take_connect_timeout
puts "queue full " + (fd < 0).to_s

t0 = now
begin
  t = Mongo::Transport.new("127.0.0.1", full_port, 1.0, nil)
  Mongo::Connection.new(t, t.address).handshake
  puts "connect_timeout 1: connected"
rescue Mongo::Error::NoServerAvailable => e
  took = now - t0
  puts "connect_timeout 1: " + e.class.to_s + " after 1s=" + (took >= 0.9 && took < 2.0).to_s
end

quiet = StuckListener.sp_net_listen_host("127.0.0.1", 0, 16)
quiet_port = StuckListener.sp_net_local_port(quiet)
t0 = now
begin
  t = Mongo::Transport.new("127.0.0.1", quiet_port, 1.0, 1.0)
  Mongo::Connection.new(t, t.address).handshake
  puts "hello never answered: handshake done"
rescue Mongo::Error::NoServerAvailable => e
  took = now - t0
  puts "hello never answered, socket_timeout 1: " + e.class.to_s + " after 1s=" + (took >= 0.9 && took < 2.0).to_s
end

held.each { |h| StuckListener.sp_net_close(h) }
StuckListener.sp_net_close(full)
StuckListener.sp_net_close(quiet)
