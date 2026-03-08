# frozen_string_literal: true

require "zlib"
require "stringio"

module OPA
  # Minimal ZIP writer and reader using only Ruby stdlib (zlib).
  # Supports the subset of ZIP needed for OPA/JAR archives: stored and
  # deflated entries, no ZIP64 or encryption.
  module ZipIO
    # Builds a ZIP archive in memory and returns the bytes.
    class Writer
      Entry = Struct.new(:name, :data, :crc32, :compressed, :offset)

      def initialize
        @entries = []
      end

      def add_entry(name, data)
        data = data.b
        crc32 = Zlib.crc32(data)
        deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
        compressed = deflater.deflate(data, Zlib::FINISH)
        deflater.close
        @entries << Entry.new(name, data, crc32, compressed, nil)
      end

      def to_bytes
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)

        # Write local file headers + data
        @entries.each do |entry|
          entry.offset = io.pos
          write_local_header(io, entry)
          io.write(entry.compressed)
        end

        # Central directory
        cd_offset = io.pos
        @entries.each { |entry| write_cd_header(io, entry) }
        cd_size = io.pos - cd_offset

        # End of central directory
        write_eocd(io, @entries.size, cd_size, cd_offset)

        io.string
      end

      private

      def write_local_header(io, entry)
        name_bytes = entry.name.b
        io.write([0x04034b50].pack("V"))          # signature
        io.write([20].pack("v"))                   # version needed
        io.write([0].pack("v"))                    # flags
        io.write([8].pack("v"))                    # compression: deflate
        io.write([0, 0].pack("vv"))                # mod time, mod date
        io.write([entry.crc32].pack("V"))          # crc32
        io.write([entry.compressed.bytesize].pack("V")) # compressed size
        io.write([entry.data.bytesize].pack("V"))  # uncompressed size
        io.write([name_bytes.bytesize].pack("v"))  # name length
        io.write([0].pack("v"))                    # extra length
        io.write(name_bytes)
      end

      def write_cd_header(io, entry)
        name_bytes = entry.name.b
        io.write([0x02014b50].pack("V"))           # signature
        io.write([20].pack("v"))                   # version made by
        io.write([20].pack("v"))                   # version needed
        io.write([0].pack("v"))                    # flags
        io.write([8].pack("v"))                    # compression: deflate
        io.write([0, 0].pack("vv"))                # mod time, mod date
        io.write([entry.crc32].pack("V"))          # crc32
        io.write([entry.compressed.bytesize].pack("V")) # compressed size
        io.write([entry.data.bytesize].pack("V"))  # uncompressed size
        io.write([name_bytes.bytesize].pack("v"))  # name length
        io.write([0].pack("v"))                    # extra length
        io.write([0].pack("v"))                    # comment length
        io.write([0].pack("v"))                    # disk number
        io.write([0].pack("v"))                    # internal attrs
        io.write([0].pack("V"))                    # external attrs
        io.write([entry.offset].pack("V"))         # local header offset
        io.write(name_bytes)
      end

      def write_eocd(io, count, cd_size, cd_offset)
        io.write([0x06054b50].pack("V"))           # signature
        io.write([0].pack("v"))                    # disk number
        io.write([0].pack("v"))                    # cd disk number
        io.write([count].pack("v"))                # entries on this disk
        io.write([count].pack("v"))                # total entries
        io.write([cd_size].pack("V"))              # cd size
        io.write([cd_offset].pack("V"))            # cd offset
        io.write([0].pack("v"))                    # comment length
      end
    end

    # Reads entries from a ZIP archive.
    class Reader
      ParsedEntry = Struct.new(:name, :data)

      def self.read(data)
        data = data.b
        entries = {}

        # Find end of central directory record
        eocd_pos = data.rindex([0x06054b50].pack("V"))
        raise "Invalid ZIP: no EOCD record" unless eocd_pos

        cd_size = data[eocd_pos + 12, 4].unpack1("V")
        cd_offset = data[eocd_pos + 16, 4].unpack1("V")
        entry_count = data[eocd_pos + 10, 2].unpack1("v")

        # Parse central directory to get entry metadata
        pos = cd_offset
        entry_count.times do
          sig = data[pos, 4].unpack1("V")
          raise "Invalid CD entry signature" unless sig == 0x02014b50

          compression = data[pos + 10, 2].unpack1("v")
          crc32 = data[pos + 16, 4].unpack1("V")
          comp_size = data[pos + 20, 4].unpack1("V")
          uncomp_size = data[pos + 24, 4].unpack1("V")
          name_len = data[pos + 28, 2].unpack1("v")
          extra_len = data[pos + 30, 2].unpack1("v")
          comment_len = data[pos + 32, 2].unpack1("v")
          local_offset = data[pos + 42, 4].unpack1("V")
          name = data[pos + 46, name_len].force_encoding("UTF-8")

          # Read from local file header to get actual data
          local_name_len = data[local_offset + 26, 2].unpack1("v")
          local_extra_len = data[local_offset + 28, 2].unpack1("v")
          data_start = local_offset + 30 + local_name_len + local_extra_len
          raw = data[data_start, comp_size]

          content = case compression
                    when 0 then raw
                    when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
                    else raise "Unsupported compression method: #{compression}"
                    end

          entries[name] = content.force_encoding("UTF-8")

          pos += 46 + name_len + extra_len + comment_len
        end

        entries
      end
    end
  end
end
