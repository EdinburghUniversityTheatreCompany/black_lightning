module DisplayHelper
  # "Tue 3 Mar", or "Tue 3 - Sat 7 Mar" when both ends share a month.
  def display_date_range(event)
    starts = event.start_date
    ends   = event.end_date

    return starts.strftime("%a %-d %b") if starts == ends
    return "#{starts.strftime('%a %-d')} – #{ends.strftime('%a %-d %b')}" if starts.month == ends.month

    "#{starts.strftime('%a %-d %b')} – #{ends.strftime('%a %-d %b')}"
  end

  # What to print in the "when" column. For an event that plays intermittently
  # the raw range is useless on a screen -- "Sep 1 - Jun 30" tells nobody when
  # to turn up -- so name the night instead.
  def display_when(event, on: Date.current)
    wdays = event.performance_wdays

    return display_date_range(event) if wdays.empty?
    return "Every #{Date::DAYNAMES[wdays.first]}" if wdays.one?

    occurrence = event.next_occurrence(on)
    occurrence ? occurrence.strftime("%a %-d %b") : display_date_range(event)
  end

  QR_MODULE_SIZE = 4

  # Inline SVG, so the page makes no external request and nothing has to be
  # added to the CSP.
  #
  # standalone: false is what makes this inlineable -- standalone: true prefixes
  # an <?xml?> declaration, which an HTML parser swallows as a bogus comment.
  # It also omits the <svg> wrapper, so we supply one with a viewBox and let CSS
  # size it.
  def display_qr_code(url, css_class: "h-64 w-64")
    qr = RQRCode::QRCode.new(url, level: :m)
    extent = qr.modules.length * QR_MODULE_SIZE
    body = qr.as_svg(module_size: QR_MODULE_SIZE, standalone: false, use_path: true,
                     color: "000000", fill: "ffffff")

    tag.svg(body.html_safe, # rubocop:disable Rails/OutputSafety
            xmlns: "http://www.w3.org/2000/svg",
            viewBox: "0 0 #{extent} #{extent}",
            class: css_class,
            role: "img",
            "aria-label": "Scan to book")
  end

  def display_booking_url(event)
    return pretix_event_url(event) if event.pretix_shown?

    "#{request.base_url}#{polymorphic_path(event)}"
  end

  # The 1920x1200 variant, not slideshow_image_url's 960x500 -- this is a 1080p
  # screen and the smaller one visibly upscales.
  #
  # fetch_image attaches a generated placeholder when nothing is uploaded, so
  # this normally always returns something. That is a write on a read path, but
  # it is idempotent and matches what the public event pages already do.
  #
  # Returns nil when the blob row exists but its object is gone from storage.
  # The panel chain guarantees a panel is *selected*; this is the only render
  # step that reaches the network, so it is the one place the never-blank
  # guarantee could still fail -- and an unattended screen would then show a 500
  # for as long as that event is in the pool. Callers must guard the image_tag
  # and degrade to text over black.
  def display_image_url(event)
    rails_representation_url(event.fetch_image.variant(large_display_variant).processed, only_path: true)
  rescue ActiveStorage::FileNotFoundError
    nil
  end
end
