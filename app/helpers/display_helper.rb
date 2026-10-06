module DisplayHelper
  def display_date_range(event)
    date_span(event.start_date, event.end_date)
  end

  # How many stretches the when-column can state. Measured in Chrome: the column is
  # 496px wide, a stretch is one unwrapped line, and two stack inside a row the title
  # and image already make 444px tall. Re-measure if the column width or text size changes.
  WHEN_MAX_BLOCKS = 2

  # The "when" column states the WHOLE run, as the poster does: five nights are one
  # range, a year of Fridays is "Every Friday". Two blocks (a matinee, a late show)
  # are both stated, a line each, whatever the date: naming only today's block hid the
  # other, and one span would claim the late show on every night. Past WHEN_MAX_BLOCKS
  # only the current-or-next block fits. A half-entered list whose every date has
  # passed states the run, never a past date.
  def display_when(event, on: Date.current)
    schedule = Event::Schedule.for(event)

    case schedule.kind
    when :weekly then "Every #{schedule.weekday_name}#{display_curtain(schedule)}"
    when :single, :range then display_run_when(event, schedule, on)
    else display_irregular_when(event, schedule, on)
    end
  end

  def display_run_when(event, schedule, on)
    block = schedule.blocks.first

    block.ends_on < on ? display_date_range(event) : display_block_when(block)
  end

  def display_irregular_when(event, schedule, on)
    blocks = schedule.blocks

    return display_date_range(event) if blocks.empty? || blocks.all? { |block| block.ends_on < on }

    return blocks.map { |block| display_block_when(block) }.join("\n") if blocks.size <= WHEN_MAX_BLOCKS

    block = blocks.find { |candidate| (candidate.starts_on..candidate.ends_on).cover?(on) } ||
            blocks.find { |candidate| candidate.ends_on >= on }

    block ? display_block_when(block) : display_date_range(event)
  end

  def display_block_when(block)
    span = date_span(block.starts_on, block.ends_on)
    first = block.occurrences.first

    "#{span}, #{time_span(first.starts_at, first.ends_at)}"
  end

  def display_curtain(schedule)
    schedule.starts_at ? ", #{short_time(schedule.starts_at)}" : ""
  end

  # The derived Event#price ("£10 / £8 concessions / £7 members") truncates in the
  # board's fixed 256px column, so bands collapse to "£10/8/7". An event without
  # bands (the archive) falls back to whatever was typed.
  def display_price(event)
    prices = event.ticket_prices

    return event.price if prices.empty?
    return "Free" if prices.all?(&:free?)

    "£#{prices.map { |price| price.formatted_amount.delete_prefix('£') }.join('/')}"
  end

  # The only logo asset that reads on this screen's black.
  def display_logo(css_class: "h-14 w-auto")
    image_tag("bedlam-logo_single-line-white-for-red.png", class: css_class, alt: "Bedlam Theatre")
  end

  QR_MODULE_SIZE = 4

  def self.qr_cache_key(url)
    [ "display/qr", QR_MODULE_SIZE, url ]
  end

  # A raster PNG, not inline SVG: SVG rendered as a blank square on Anthias even
  # with an intrinsic size. img_src already allows data:. Encoding costs ~15ms and
  # the Pi re-fetches these pages forever, so the image is cached by URL.
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

  # The programme QR always resolves to something: a footer that vanishes for one
  # show reads as a broken slide, so the fallback is the event's own page.
  def display_programme_url(event)
    event.digital_programme_url.presence || display_event_url(event)
  end

  def display_event_url(event)
    "#{request.base_url}#{event_page_path(event)}"
  end

  # A bare Event has no show route (`resources :events` is index-only) and
  # polymorphic_path would raise mid-render, blanking the screen. Fall back to the listing.
  def event_page_path(event)
    polymorphic_path(event)
  rescue NoMethodError, ActionController::UrlGenerationError
    events_path
  end

  # An editable block for the screen. Its markdown links mean nothing where nobody
  # can click, and the QR is the call to action, so keep the words and drop the
  # anchors. The first `false` matches the home page widget: display_block writes
  # when the stored admin_page differs, which the re-fetching Pi would do forever.
  # The second drops the Edit button, whose word the sanitizer would keep.
  def display_block_text(name)
    sanitize(display_block(name, false, false), tags: %w[p br strong em ul ol li], attributes: [])
  end

  # The credits fit a 1080p screen by stepping the type down. Measured at 1920x1080:
  # the page header leaves CREDITS_COLUMN_HEIGHT, a name costs its line height plus
  # an 8px gap (CREDITS_ROW_STRIDES), the QR is a flat 160px. Pixels, not rows: the
  # QR is a different fraction of a row at each size (under three at text-5xl, nearly
  # five at text-xl), and a fixed count pushed it off the screen for an 18-name cast.
  CREDITS_COLUMN_HEIGHT = 795
  CREDITS_HEADING_HEIGHT = 56
  CREDITS_LIST_HEIGHT = CREDITS_COLUMN_HEIGHT - CREDITS_HEADING_HEIGHT
  CREDITS_QR_HEIGHT = 160
  # Air above a heading that follows another section (flowed layout only). Modest on
  # purpose: it competes with name size, and at 40px an 18-cast, 2-crew show missed
  # text-5xl by one pixel.
  CREDITS_SECTION_GAP = 32
  CREDITS_ROW_STRIDES = {
    "text-5xl" => 56, "text-4xl" => 48, "text-3xl" => 44, "text-2xl" => 40,
    "text-xl" => 36, "text-base" => 32
  }.freeze

  # Side by side (Cast against Company) is the clearer read but sizes off the longer
  # list, so 3 cast against 18 crew wastes a column. Flowed runs both lists down the
  # first column and into the second. Whichever allows bigger names wins, a tie going
  # to side by side: flow only wins where a column was going to waste.
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

  # What one of the two flowed columns holds: both lists and headings, halved.
  # An empty list prints no heading.
  def flowed_height(cast_count, crew_count, stride)
    sections = [ cast_count, crew_count ].count(&:positive?)
    headings = sections * CREDITS_HEADING_HEIGHT + (sections > 1 ? CREDITS_SECTION_GAP : 0)

    ((headings + (cast_count + crew_count) * stride) / 2.0).ceil
  end

  # A tie goes to side by side, and so does neither layout fitting.
  def prefer_flowed?(cast_count, crew_count, side, flowed)
    return false if flowed.nil?
    return true if side.nil? && flowed

    smallest = CREDITS_ROW_STRIDES.values.last
    return flowed_height(cast_count, crew_count, smallest) < side_by_side_height(cast_count, crew_count, smallest) if side.nil?

    flowed < side
  end

  # nil = nothing fitted (a company past what the screen holds): shrink fully and let the caps clip.
  def credits_size_at(index)
    (index && CREDITS_ROW_STRIDES.keys[index]) || CREDITS_ROW_STRIDES.keys.last
  end

  def flowed_layout(flowed)
    { mode: :flowed,
      name_size: credits_size_at(flowed),
      # The QR is a footer under both columns: the flow balances, so its height
      # comes off the flow before it runs.
      flow_height: credits_flow_height }
  end

  def side_by_side_layout(cast_count, crew_count, side)
    # The QR goes under the shorter list (nearly always the cast, bottom left), so it takes spare room.
    qr_in_cast_column = cast_count <= crew_count
    name_size = credits_size_at(side)
    tallest = side_by_side_height(cast_count, crew_count, CREDITS_ROW_STRIDES.fetch(name_size))

    { mode: :side_by_side,
      name_size: name_size,
      qr_in_cast_column: qr_in_cast_column,
      # A hard cap per list, so a name that wraps (the arithmetic assumes one line
      # per person) clips its own list and never the QR beneath it.
      cast_list_height: credits_column_list_height(qr_in_cast_column),
      crew_list_height: credits_column_list_height(!qr_in_cast_column),
      # Centre the columns unless the names need all the space: then start at the
      # top so a long list loses its tail, not its heading.
      block_position: tallest > CREDITS_LIST_HEIGHT ? "content-start" : "content-center" }
  end

  def credits_column_list_height(carries_qr)
    CREDITS_COLUMN_HEIGHT - (carries_qr ? CREDITS_QR_HEIGHT : 0)
  end

  public

  # Titles step down by length rather than truncate: naming the show is the page's
  # job. The text block is anchored to the bottom, so a taller title grows up into
  # the artwork instead of pushing the dates and price off screen.
  TITLE_SIZES = { 22 => "text-8xl", 46 => "text-7xl", 80 => "text-6xl" }.freeze
  SMALLEST_TITLE_SIZE = "text-5xl".freeze

  def display_title_size(title)
    length = title.to_s.length
    TITLE_SIZES.each { |max_length, size| return size if length <= max_length }

    SMALLEST_TITLE_SIZE
  end

  # The 1920x1200 variant: slideshow_image_url's 960x500 visibly upscales on a 1080p
  # screen. fetch_image attaches a placeholder when nothing is uploaded (an
  # idempotent write, as on the public pages).
  #
  # nil when the blob row exists but its object is gone from storage. This is the
  # only render step that reaches storage, so callers must guard the image_tag and
  # degrade to text over black, or the unattended screen shows a 500 for as long as
  # the event is in the pool.
  def display_image_url(event)
    rails_representation_url(event.fetch_image.variant(large_display_variant).processed, only_path: true)
  rescue ActiveStorage::FileNotFoundError
    nil
  end
end
