# The package loads and names its version. Dual-runtime: no snapshot is
# committed, so `spin test` diffs the compiled run against CRuby.
require "mongo/version"

puts "version " + Mongo::VERSION
parts = Mongo::VERSION.split(".")
puts "semver " + (parts.length == 3 && parts.all? { |p| p.to_i.to_s == p }).to_s
