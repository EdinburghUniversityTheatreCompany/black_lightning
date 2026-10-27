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
    return "Every #{schedule.weekday_name}, #{short_time(schedule.starts_at)}" if schedule.kind == :weekly

    blocks = schedule.blocks
    current = blocks.find { |block| block.ends_on >= on }
    return display_date_range(event) unless current
    return blocks.map { |block| display_block_when(block) }.join("\n") if blocks.size <= WHEN_MAX_BLOCKS

    display_block_when(current)
  end

  def display_block_when(block)
    span = date_span(block.starts_on, block.ends_on)
    first = block.occurrences.first

    "#{span}, #{time_span(first.starts_at, first.ends_at)}"
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

  # The red label every panel opens with ("What's On", "Tonight", "Latest News"), one size
  # on every screen so the event's name is the only big type. Margins are the caller's.
  def display_label(text, tag: :p, css_class: nil)
    content_tag(tag, text, class: [ "text-4xl font-bold uppercase tracking-[0.3em] text-display-accent", css_class ].compact.join(" "))
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
      Base64.strict_encode64(
        RQRCode::QRCode.new(url, level: :m).as_png(module_px_size: QR_MODULE_SIZE * 2, border_modules: 2).to_s
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

  # A bare Event has no show route (`resources :events` is index-only) and
  # polymorphic_url would raise mid-render, blanking the screen. Fall back to the listing.
  def display_event_url(event)
    polymorphic_url(event)
  rescue NoMethodError, ActionController::UrlGenerationError
    events_url
  end

  # An editable block for the screen. Its markdown links mean nothing where nobody
  # can click, and the QR is the call to action, so keep the words and drop the
  # anchors. The first `false` matches the home page widget: display_block writes
  # when the stored admin_page differs, which the re-fetching Pi would do forever.
  # The second drops the Edit button, whose word the sanitizer would keep.
  def display_block_text(name)
    sanitize(display_block(name, false, false), tags: %w[p br strong em ul ol li], attributes: [])
  end

  # The credits are one list (cast, then company) flowing down CSS columns, and
  # they fit a 1080p screen by stepping the type down first, then widening the
  # flow. Measured in Chrome at 1920x1080:
  #   - the panel chrome pinned in _credits.html.erb (CREDITS_CHROME_REM) leaves
  #     CREDITS_WINDOW_HEIGHT for the list;
  #   - CREDITS_ROW_STRIDES is a name's line height plus the 8px list gap;
  #   - CREDITS_FONT_PX is the rendered font size at each step, and
  #     CREDITS_CHAR_EM the mean advance of one character of mixed-case Source
  #     Sans 3 (a semibold name, then a lighter role) as a fraction of it —
  #     re-measure alongside the strides whenever either changes.
  # Pixels, not people: roles run long ("Assistant Technical Stage Manager"),
  # and a person-count promise wraps into a scroll the moment names wrap.
  CREDITS_CHROME_REM = 26.8
  CREDITS_WINDOW_HEIGHT = (1080 - CREDITS_CHROME_REM * 16).floor # 651
  CREDITS_CONTENT_WIDTH = 1920 - 2 * 64                          # px-16 both sides
  CREDITS_COLUMN_GAP = 64                                        # gap-16
  CREDITS_HEADING_HEIGHT = 56
  # Air above a heading that follows another section (the company's mt-8). Modest
  # on purpose: it competes with name size.
  CREDITS_SECTION_GAP = 32
  CREDITS_ROW_STRIDES = {
    "text-5xl" => 56, "text-4xl" => 48, "text-3xl" => 44, "text-2xl" => 40,
    "text-xl" => 36, "text-base" => 32
  }.freeze
  CREDITS_FONT_PX = {
    "text-5xl" => 48, "text-4xl" => 36, "text-3xl" => 30, "text-2xl" => 24,
    "text-xl" => 20, "text-base" => 16
  }.freeze
  # Source Sans 3's lowercase and space advance measure 0.45em, but the model is
  # only ever safe in one direction: too small a figure promises a fit that
  # wraps into the scroll. 0.48 was the smallest figure at which 300 random
  # companies all fit at the size chosen; 0.45 broke 19 of them.
  CREDITS_CHAR_EM = 0.48

  # The biggest type first, then the fewest columns (2 to 4) that fit one screen.
  # Only when nothing fits at any size does the layout give up and take the
  # smallest text in the most columns: the marquee is the safety net for that
  # case alone, and CSS columns cannot scroll cleanly (every column moves at
  # once, so the fold cuts the first column mid-list), which is why the net is
  # the last resort and not the design.
  #
  # `fits:` tells the markup whether the chosen layout fits the window. When it
  # does, the track is at most the window tall and the marquee's translateY
  # clamps to zero — but only if the tail-slack div is absent too, so the
  # template renders that one only when `fits` is false. A slack inside a track
  # that fits would make it taller than the window by exactly its own height and
  # start a scroll that has nothing to show.
  def display_credits_layout(cast_members, crew_members)
    sections = [ cast_members, crew_members ].count(&:any?)
    headings = sections * CREDITS_HEADING_HEIGHT + (sections > 1 ? CREDITS_SECTION_GAP : 0)

    CREDITS_ROW_STRIDES.each do |size, stride|
      2.upto(4) do |columns|
        chars_per_line = credits_chars_per_line(columns, size)
        lines = credits_lines(cast_members, crew_members, chars_per_line)

        # CSS multicol balances the flow across the columns, so the track's height
        # is roughly the content's total divided by the column count.
        if headings + lines * stride <= CREDITS_WINDOW_HEIGHT * columns
          return { name_size: size, columns: columns, fits: true }
        end
      end
    end

    { name_size: CREDITS_ROW_STRIDES.keys.last, columns: 4, fits: false }
  end

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

  # The wash is mixed over the panel's neutral-950 and each stop then darkened, in
  # linear light, to at most WASH_MAX_LUMINANCE: there the roles (neutral-400) keep
  # 4.5:1 and the red label 3:1, whatever the poster. Pale bands come out dark grey.
  WASH_BASE = [ 10, 10, 10 ].freeze
  WASH_ALPHAS = [ 0.7, 0.5, 0.7 ].freeze
  WASH_MAX_LUMINANCE = 0.04

  # A gradient from the event artwork's key colours, for the credits panel's
  # background. nil (plain black) when no artwork, no palette, or anything at all
  # went wrong: the unattended screen must never 500 over a background wash.
  def display_ambient_gradient(event)
    colours = Display::Palette.for(event)
    return nil if colours.blank?

    stops = WASH_ALPHAS.zip(%w[0% 50% 100%]).each_with_index.map do |(alpha, at), i|
      "rgb(#{wash_stop(colours[i] || colours.last, alpha).join(', ')}) #{at}"
    end
    "background-image: linear-gradient(160deg, #{stops.join(', ')})"
  rescue StandardError => e
    Rails.logger.warn("display_ambient_gradient failed: #{e.class}")
    nil
  end

  private

  def credits_column_width(columns)
    (CREDITS_CONTENT_WIDTH - (columns - 1) * CREDITS_COLUMN_GAP) / columns
  end

  def credits_chars_per_line(columns, size)
    (credits_column_width(columns) / (CREDITS_CHAR_EM * CREDITS_FONT_PX.fetch(size))).floor
  end

  # Each entry is "Name Role" on one or more lines: estimate the lines it needs
  # from the characters that fit a line, the way Display::Panels::News budgets
  # headlines with CHARS_PER_LINE.
  def credits_lines(cast_members, crew_members, chars_per_line)
    (cast_members + crew_members).sum do |(name, detail)|
      credits_entry_lines("#{name} #{detail}", chars_per_line)
    end
  end

  def wash_stop(rgb, alpha)
    linear = rgb.zip(WASH_BASE).map { |c, base| wash_linear(c * alpha + base * (1 - alpha)) }
    luminance = [ 0.2126, 0.7152, 0.0722 ].zip(linear).sum { |weight, c| weight * c }
    scale = [ WASH_MAX_LUMINANCE / luminance, 1 ].min
    # floor, not round: rounding up could land a channel back over the cap.
    linear.map { |c| (wash_encode(c * scale) * 255).floor }
  end

  def wash_linear(channel)
    c = channel / 255.0
    c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
  end

  def wash_encode(linear)
    linear <= 0.0031308 ? linear * 12.92 : 1.055 * linear**(1 / 2.4) - 0.055
  end

  # Greedy wrap, one word at a time: a word that does not fit starts a new line.
  # Dividing the characters by the line width is cheaper but blind to where the
  # breaks fall, and where they fall is what decides the height — once "Assistant
  # Technical Stage Manager" wraps, the rest of that line is dead space, and a
  # long name can leave a line mostly empty.
  def credits_entry_lines(text, chars_per_line)
    lines = 1
    used = 0
    text.to_s.split.each do |word|
      if used.zero?
        used = word.length
      elsif used + 1 + word.length <= chars_per_line
        used += 1 + word.length
      else
        lines += 1
        used = word.length
      end
    end
    lines
  end
end
