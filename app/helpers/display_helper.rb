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

  # The white wordmark with the red arch -- the only logo asset that reads on
  # this screen's black. Kept small on the content panels: the show is the
  # message, the logo is the signature.
  def display_logo(css_class: "h-14 w-auto")
    image_tag("bedlam-logo_single-line-white-for-red.png", class: css_class, alt: "Bedlam Theatre")
  end

  QR_MODULE_SIZE = 4

  # A raster PNG rather than inline SVG, and that is not a style preference.
  # The SVG version rendered as a blank square on the Anthias player while
  # looking correct in a desktop browser, and survived being given an explicit
  # intrinsic size, so the cause is something about that engine's SVG support
  # rather than one fixable attribute. An <img> has no such failure mode.
  # img_src already allows :data, so this asks nothing of the CSP and still
  # makes no external request.
  #
  # Encoding costs about 15ms and the code for a given URL never changes, while
  # the Pi re-fetches these pages every few seconds forever -- so the encoded
  # image is cached and only the tag is rebuilt per request.
  def self.qr_cache_key(url)
    [ "display/qr", QR_MODULE_SIZE, url ]
  end

  def display_qr_code(url, css_class: "h-64 w-64", label: "Scan to book")
    encoded = Rails.cache.fetch(DisplayHelper.qr_cache_key(url), expires_in: 1.week) do
      qr = RQRCode::QRCode.new(url, level: :m)
      Base64.strict_encode64(
        RQRCode::Renderers::PNG.render(qr, unit: QR_MODULE_SIZE * 2, offset: QR_MODULE_SIZE * 4)
      )
    end

    image_tag "data:image/png;base64,#{encoded}",
              class: "shrink-0 #{css_class}", alt: label, loading: "eager"
  end

  def display_booking_url(event)
    return pretix_event_url(event) if event.pretix_shown?

    "#{request.base_url}#{event_page_path(event)}"
  end

  # Show, Workshop and Season each have a public show route; a bare Event does
  # not (`resources :events` is index-only), and polymorphic_path would raise
  # mid-render -- which on this screen means a blank box office, not a 500 page
  # somebody sees. The events listing is the honest fallback.
  def event_page_path(event)
    polymorphic_path(event)
  rescue NoMethodError, ActionController::UrlGenerationError
    events_path
  end

  # The news body is markdown, and truncating the raw source puts "##", "**" and
  # "[text](https://...)" on a wall-mounted screen. Render it, strip the tags,
  # and undo the sanitizer's entity escaping -- truncate escapes again on the way
  # out, so leaving them would print "&amp;".
  # An editable block, rendered for the screen. The site's blocks carry markdown
  # links ("submit your own"), which mean nothing where nobody can touch them --
  # the QR beside this is the call to action, so keep the words and drop the
  # anchors.
  #
  # The first `false` matches what the home page widget passes: display_block
  # only writes when the stored admin_page differs, and the Pi re-fetches this
  # page every few seconds forever, so a write here would never stop. The second
  # drops the block's Edit button -- the sanitizer strips its anchor but keeps
  # the word, so an admin browsing the screen leaves a bare "Edit" in the copy.
  def display_block_text(name)
    sanitize(display_block(name, false, false), tags: %w[p br strong em ul ol li], attributes: [])
  end

  # Poster titles are sized by length rather than truncated: naming the show is
  # the page's whole job, so a long title steps down instead of being cut off.
  # Two lines at the top size is fine -- the text block is anchored to the bottom
  # of the page, so a taller title grows up into the artwork rather than pushing
  # the dates and price off screen.
  TITLE_SIZES = { 22 => "text-8xl", 46 => "text-7xl", 80 => "text-6xl" }.freeze
  SMALLEST_TITLE_SIZE = "text-5xl".freeze

  def display_title_size(title)
    length = title.to_s.length
    TITLE_SIZES.each { |max_length, size| return size if length <= max_length }

    SMALLEST_TITLE_SIZE
  end

  def display_plain_text(markdown, length:)
    text = CGI.unescapeHTML(strip_tags(render_markdown(markdown)).to_s).squish

    truncate(text, length: length, separator: " ")
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
