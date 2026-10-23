# Malformed BSON that must raise rather than read past the input. Shared
# with the twin, oracle/bson_malformed.rb, which decodes with the gem.

# A document around the hex of its elements, with the right length.
def bson_doc_hex(body)
  b = [body].pack("H*")
  [b.bytesize + 5].pack("l<") + b + [0].pack("C")
end

def bson_malformed_cases
  [
    ["empty input", ""],
    ["two bytes", ["0500"].pack("H*")],
    ["length past the end", ["ff0000000a6100" + "00"].pack("H*")],
    ["length under five", ["0400000000"].pack("H*")],
    ["no closing nul", ["0500000001"].pack("H*")],
    ["length short of the elements", ["0b000000" + "1061000100000000"].pack("H*") + [0].pack("C")],
    ["unterminated key", ["0a000000" + "0a616161616161"].pack("H*")],
    ["string length past the end", bson_doc_hex("026100" + "ff000000" + "6200")],
    ["string length zero", bson_doc_hex("026100" + "00000000")],
    ["string without its nul", bson_doc_hex("026100" + "02000000" + "6262")],
    ["string not UTF-8", bson_doc_hex("026100" + "02000000" + "ff00")],
    ["int32 cut short", bson_doc_hex("106100" + "0100")],
    ["int64 cut short", bson_doc_hex("126100" + "010000")],
    ["double cut short", bson_doc_hex("016100" + "000000")],
    ["ObjectId cut short", bson_doc_hex("076100" + "0102030405")],
    ["boolean of 2", bson_doc_hex("086100" + "02")],
    ["binary past the end", bson_doc_hex("056100" + "ff000000" + "00" + "6162")],
    ["nested document past the end", bson_doc_hex("036100" + "ff000000" + "00")],
    ["unknown type 0x20", bson_doc_hex("206100")]
  ]
end

# Types the gem decodes and spinel-mongo leaves out (see the README's
# ledger). They raise UnsupportedType here, so they have no twin.
def bson_left_out_cases
  [
    ["undefined (0x06)", bson_doc_hex("066100")],
    ["regular expression (0x0b)", bson_doc_hex("0b6100" + "7800" + "00")],
    ["JavaScript (0x0d)", bson_doc_hex("0d6100" + "0200000078" + "00")],
    ["timestamp (0x11)", bson_doc_hex("116100" + "0100000002000000")],
    ["Decimal128 (0x13)", bson_doc_hex("136100" + "00" * 16)],
    ["min key (0xff)", bson_doc_hex("ff6100")],
    ["max key (0x7f)", bson_doc_hex("7f6100")]
  ]
end
