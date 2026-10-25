# Spinel-only helpers for the live tests: each starts its own mongod on
# a private port with a throwaway --dbpath under build/live/, and stops
# it at the end. Needs mongod on PATH.
module LiveShell
  ffi_func :sp_net_shell_capture, [:str, :int], :binstr
end

def live_sh(cmd)
  LiveShell.sp_net_shell_capture(cmd, 4096)
end

def live_dir(name)
  "build/live/" + name
end

# --fork returns once mongod is ready for connections. Test commands
# are on for the sleep command the timeout case uses. extra adds
# options, such as --auth.
def live_mongod_start(name, port, extra = "")
  dir = live_dir(name)
  live_sh("rm -rf " + dir + " && mkdir -p " + dir + "/db")
  live_sh("mongod --port " + port.to_s + " --bind_ip 127.0.0.1 --dbpath " + dir + "/db --fork" +
          " --logpath " + dir + "/mongod.log --wiredTigerCacheSizeGB 0.25" +
          " --setParameter enableTestCommands=1 " + extra + " > /dev/null 2>&1")
  nil
end

def live_mongod_stop(name)
  live_sh("mongod --shutdown --dbpath " + live_dir(name) + "/db > /dev/null 2>&1")
  nil
end

# A connection that has done its handshake.
def live_connect(port, socket_timeout)
  t = Mongo::Transport.new("127.0.0.1", port, 5.0, socket_timeout)
  c = Mongo::Connection.new(t, t.address)
  c.handshake
  c
end

def live_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
