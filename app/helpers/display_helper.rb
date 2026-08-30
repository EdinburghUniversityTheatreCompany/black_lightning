module DisplayHelper
  # "Tue 3 Mar", or "Tue 3 - Sat 7 Mar" when both ends share a month.
  def display_date_range(event)
    starts = event.start_date
    ends   = event.end_date

    return starts.strftime("%a %-d %b") if starts == ends
    return "#{starts.strftime('%a %-d')} – #{ends.strftime('%a %-d %b')}" if starts.month == ends.month

    "#{starts.strftime('%a %-d %b')} – #{ends.strftime('%a %-d %b')}"
  end

  # "7.30pm", "8pm". British house style, and the minutes are dropped on the
  # hour rather than printing a bare ":00" nobody says out loud.
  def display_time(time)
    time.min.zero? ? time.strftime("%-l%P") : time.strftime("%-l.%M%P")
  end

  # What to print in the "when" column. For an event that plays intermittently
  # the raw range is useless on a screen -- "Sep 1 - Jun 30" tells nobody when
  # to turn up -- so name the next performance and its curtain time instead.
  #
  # An event with no occurrences, which is every archive row, falls back to the
  # range exactly as it did before performances were stored.
  def display_when(event, on: Date.current)
    occurrence = event.next_occurrence_at(on)

    return display_date_range(event) if occurrence.nil?

    "#{occurrence.starts_at.strftime('%a %-d %b')}, #{display_time(occurrence.starts_at)}"
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

    display_event_url(event)
  end

  # The programme QR always resolves to something. A footer that appears for one
  # show and vanishes for the next reads as a broken slide from across the room,
  # and every event has a page on the site even when nobody has made a
  # programme -- so the fallback is that page rather than nothing.
  def display_programme_url(event)
    event.digital_programme_url.presence || display_event_url(event)
  end

  def display_event_url(event)
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

  # Fitting the credits to a 1080p screen. A 90-seat house still puts up big
  # casts, so the type steps down rather than the list running off a screen
  # nobody can scroll.
  #
  # Measured in the browser at 1920x1080: the page header leaves
  # CREDITS_COLUMN_HEIGHT for a column, a heading costs CREDITS_HEADING_HEIGHT of
  # it, a name costs its line height plus the 8px gap under it
  # (CREDITS_ROW_STRIDES), and the QR block is a flat 160px wherever it lands.
  #
  # Pixels rather than a row count, because the QR is not a whole number of rows
  # and is a different fraction of one at each size -- under three at text-5xl,
  # nearly five at text-xl. Counting it as a fixed four let an 18-name cast size
  # for the names alone and pushed the QR off the bottom of the screen.
  CREDITS_COLUMN_HEIGHT = 795
  CREDITS_HEADING_HEIGHT = 56
  CREDITS_LIST_HEIGHT = CREDITS_COLUMN_HEIGHT - CREDITS_HEADING_HEIGHT
  CREDITS_QR_HEIGHT = 160
  # Air above a heading that follows another section, which only the flowed
  # layout has -- side by side puts one section in each column. Deliberately
  # modest: it competes directly with name size, and at 40px an 18-cast, 2-crew
  # show missed text-5xl by a single pixel. Four times the gap between names is
  # plenty to read as a new section.
  CREDITS_SECTION_GAP = 32
  CREDITS_ROW_STRIDES = {
    "text-5xl" => 56, "text-4xl" => 48, "text-3xl" => 44, "text-2xl" => 40,
    "text-xl" => 36, "text-base" => 32
  }.freeze

  # Two ways to lay the slide out.
  #
  # SIDE BY SIDE is Cast in one column against Company in the other, and it is
  # the clearer read: the eye finds "who played whom" in one place. But it sizes
  # off the LONGER list, so three cast against eighteen crew wastes a whole
  # column and shrinks every name to fit the crew list into half the screen.
  #
  # FLOWED runs both lists as one sequence down the first column and on into the
  # second, headings and all, so the two share the space evenly.
  #
  # Which one is used is decided by which lets the names be BIGGER, with a tie
  # going to side by side. That needs no threshold on "how lopsided is lopsided":
  # flow only wins where a column was going to waste, and it is exactly then
  # that it buys a size step -- three steps, for an 18-cast, 2-crew show.
  def display_credits_layout(cast_count, crew_count)
    side = credits_first_fit { |stride| side_by_side_height(cast_count, crew_count, stride) <= CREDITS_LIST_HEIGHT }
    flowed = credits_first_fit { |stride| flowed_height(cast_count, crew_count, stride) <= credits_flow_height }

    if prefer_flowed?(cast_count, crew_count, side, flowed)
      flowed_layout(flowed)
    else
      side_by_side_layout(cast_count, crew_count, side)
    end
  end

  private

  # The index of the first size the block yields true for, or nil if none does.
  def credits_first_fit
    CREDITS_ROW_STRIDES.values.index { |stride| yield(stride) }
  end

  def credits_flow_height
    CREDITS_COLUMN_HEIGHT - CREDITS_QR_HEIGHT
  end

  def side_by_side_height(cast_count, crew_count, stride)
    qr_in_cast_column = cast_count <= crew_count

    [ cast_count * stride + (qr_in_cast_column ? CREDITS_QR_HEIGHT : 0),
      crew_count * stride + (qr_in_cast_column ? 0 : CREDITS_QR_HEIGHT) ].max
  end

  # Both lists and their headings, halved: what one of the two flowed columns
  # has to hold. A list with nobody in it prints no heading, so it costs none.
  def flowed_height(cast_count, crew_count, stride)
    sections = [ cast_count, crew_count ].count(&:positive?)
    headings = sections * CREDITS_HEADING_HEIGHT + (sections > 1 ? CREDITS_SECTION_GAP : 0)

    ((headings + (cast_count + crew_count) * stride) / 2.0).ceil
  end

  # A tie goes to side by side, so a normal show keeps Cast beside Company and
  # only a wasted column moves. When NEITHER fits -- a company past what this
  # screen holds at any size -- the smallest size is going to be used either way,
  # so it comes down to which loses less off the end.
  def prefer_flowed?(cast_count, crew_count, side, flowed)
    return false if flowed.nil?
    return true if side.nil? && flowed

    smallest = CREDITS_ROW_STRIDES.values.last
    return flowed_height(cast_count, crew_count, smallest) < side_by_side_height(cast_count, crew_count, smallest) if side.nil?

    flowed < side
  end

  # nil index = nothing on the scale fitted, which is a company past what this
  # screen holds at any size. Shrink as far as we can and let the caps clip.
  def credits_size_at(index)
    (index && CREDITS_ROW_STRIDES.keys[index]) || CREDITS_ROW_STRIDES.keys.last
  end

  def flowed_layout(flowed)
    { mode: :flowed,
      name_size: credits_size_at(flowed),
      # The QR is a footer under both columns here rather than under one of
      # them: the flow balances, so neither column has spare room the other
      # does not, and the height it needs is taken off the flow before it runs.
      flow_height: credits_flow_height }
  end

  def side_by_side_layout(cast_count, crew_count, side)
    # The QR goes under whichever list is SHORTER, so the room it takes is room
    # that column had going spare and the other keeps its full height. That is
    # nearly always the cast, which puts it bottom left.
    qr_in_cast_column = cast_count <= crew_count
    name_size = credits_size_at(side)
    tallest = side_by_side_height(cast_count, crew_count, CREDITS_ROW_STRIDES.fetch(name_size))

    { mode: :side_by_side,
      name_size: name_size,
      qr_in_cast_column: qr_in_cast_column,
      # A hard cap on each list, so it can only ever push itself off the bottom
      # and never the QR under it. The arithmetic assumes one line per person,
      # which a long enough name against a character name breaks -- and the code
      # is the one thing here that leads to the names it just cut.
      cast_list_height: credits_column_list_height(qr_in_cast_column),
      crew_list_height: credits_column_list_height(!qr_in_cast_column),
      # Centre the columns in the space they leave -- unless the names need all
      # of it, in which case start at the top so a long list loses its tail
      # rather than its heading.
      block_position: tallest > CREDITS_LIST_HEIGHT ? "content-start" : "content-center" }
  end

  def credits_column_list_height(carries_qr)
    CREDITS_COLUMN_HEIGHT - (carries_qr ? CREDITS_QR_HEIGHT : 0)
  end

  public

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
