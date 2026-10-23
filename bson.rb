# BSON for spinel-mongo: the subset of the bson gem (5.x) the driver
# needs. Documents are Hashes in, BSON::Document out; see README.md for
# the types and what is left out.
require "bson/errors"
require "bson/values"
require "bson/object_id"
require "bson/document"
require "bson/encoder"
require "bson/reader"

module BSON
  # Encodes a Hash (or BSON::Document) as a BSON document: a binary String.
  def self.encode(doc)
    enc = BSON::Encoder.new
    enc.document(doc)
    enc.bytes
  end

  # Decodes one BSON document from the start of a binary String.
  def self.decode(bytes)
    BSON::Reader.new(bytes).document
  end
end
