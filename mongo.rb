# mongo (spinel-mongo): a pure Spinel-Ruby MongoDB driver, a
# subset-compatible port of the mongo gem. See README.md.
#
# Spinel-only, since the transport binds sp_net. A program run under
# CRuby gets the gem from `require "mongo"`; this package's own tests
# that run under both runtimes require the pure files directly.
require "bson"
require "mongo/version"
require "mongo/errors"
require "mongo/wire"
require "mongo/connection"
require "mongo/sock"
require "mongo/transport"
