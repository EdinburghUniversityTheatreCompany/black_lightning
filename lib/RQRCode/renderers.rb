module RQRCode
  # :nocov:
  module Renderers
    class SVG
      class << self
        # Render the SVG from the qrcode string provided from the RQRCode gem
        #   Options:
        #   offset - Padding around the QR Code (e.g. 10)
        #   unit   - How many pixels per module (Default: 11)
        #   fill   - Background color (e.g "ffffff" or :white)
        #   color  - Foreground color for the code (e.g. "000000" or :black)

        def render(qrcode, options = {})
          offset  = options[:offset].to_i || 0
          color   = options[:color]       || "000"
          unit    = options[:unit]        || 11

          modules   = qrcode.modules
          size      = modules.length
          dimension = (size * unit) + (2 * offset)

          xml_tag   = %(<?xml version="1.0" standalone="yes"?>)
          open_tag  = %(<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:ev="http://www.w3.org/2001/xml-events" width="#{dimension}" height="#{dimension}">)
          close_tag = "</svg>"

          result = []
          modules.each_with_index do |row, r|
            tmp = []
            row.each_with_index do |dark, c|
              next unless dark
              x = c * unit + offset
              y = r * unit + offset
              tmp << %(<rect width="#{unit}" height="#{unit}" x="#{x}" y="#{y}" style="fill:##{color}"/>)
            end
            result << tmp.join
          end

          if options[:fill]
            result.unshift %(<rect width="#{dimension}" height="#{dimension}" x="0" y="0" style="fill:##{options[:fill]}"/>)
          end

          [ xml_tag, open_tag, result, close_tag ].flatten.join("\n")
        end
      end
    end

    class PNG
      def self.render(qrcode, options = {})
        unit   = options[:unit]        || 11
        offset = options[:offset].to_i || 0

        modules     = qrcode.modules
        size        = modules.length
        pixel_array = modules.map { |row| row.map { |dark| dark ? 0 : 255 } }

        img = Vips::Image.new_from_array(pixel_array).cast(:uchar)
        img = img.zoom(unit, unit) if unit > 1

        if offset > 0
          padded = size * unit + 2 * offset
          img = img.embed(offset, offset, padded, padded, extend: :white)
        end

        img.write_to_buffer(".png")
      end
    end
  end
  # :nocov:
end
