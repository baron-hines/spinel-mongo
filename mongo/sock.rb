# sp_net externs for Mongo::Transport. A top-level module, as Spinel's
# FFI plumbing wants, named so it can sit beside other packages' sp_net
# modules in one program (duplicate extern declarations are fine).
#
# Spinel-only: CRuby has no ffi_func, so the files that run under both
# runtimes (BSON, the wire layer, the connection) never require this.
module MongoSock
  # connect with a deadline in seconds (negative: none), and whether the
  # last timed connect gave up on the deadline rather than being refused.
  ffi_func :sp_net_connect_timeout,      [:str, :int, :double], :int
  ffi_func :sp_net_take_connect_timeout, [],                    :int
  ffi_func :sp_net_close,                [:int],                :int
  # Writes all n bytes (NULs included): 0, or -1 when the connection is
  # gone.
  ffi_func :sp_net_write_bytes,          [:int, :str, :int],    :int
  # Up to max bytes, "" at EOF or on the deadline (negative: none), and
  # whether the last timed read gave up on the deadline. A blocked read
  # parks the green thread under SP_THREADS.
  ffi_func :sp_net_recv_some_timeout,    [:int, :int, :double], :binstr
  ffi_func :sp_net_take_recv_timeout,    [],                    :int
end
