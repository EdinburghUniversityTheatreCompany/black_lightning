module Display
  module Panels
    class News < Base
      # The slide is read from across a room in about twelve seconds, so the list
      # is bounded by the space it has rather than by a count. Headlines are set
      # at one constant size and taken until that space runs out, which means a
      # newsletter title long enough to wrap crowds out the ones below it. That
      # is the deliberate trade: the alternative is an ellipsis through a
      # headline, and a half-read headline tells you less than no headline.
      MAX_ITEMS = 4

      # Pixels of the 1080-tall screen. Every figure below is one Tailwind class
      # in display/panels/_news.html.erb; change a class and re-measure, because
      # nothing checks these at runtime.
      #
      #   1080 - py-16 top+bottom (128) - the "Latest News" label and its mb-10
      #   (40 + 40) - the QR block and its mt-8 (160 + 32) = 680.
      LIST_HEIGHT_PX = 680
      # text-5xl (48px) at leading-tight (1.25).
      TITLE_LINE_PX = 60
      # mt-3 (12px) plus the date's text-3xl line box (36px).
      DATE_BLOCK_PX = 48
      # gap-8, charged between items and not after the last one.
      GAP_PX = 32

      # Measured in Chrome across the 1728px the list has, at text-5xl bold: 76
      # characters fit on a line in the mixed case these headlines are written
      # in, 66 in an all-caps worst case. Sitting between the two reads the real
      # headline lengths as the lines they actually render as, with margin for a
      # wider-than-average title. Setting it too low is not a safe error: it
      # charges a headline for lines that are never drawn and drops the ones
      # below it.
      CHARS_PER_LINE = 68

      def available?
        articles.any?
      end

      def partial
        "display/panels/news"
      end

      def locals
        { articles: articles }
      end

      private

      # News carries default_scope -> { order("publish_date DESC") }, so these
      # arrive newest first.
      def articles
        @articles ||= fill_to_budget(::News.where(show_public: true).current.limit(MAX_ITEMS).to_a)
      end

      def fill_to_budget(candidates)
        used = 0

        candidates.take_while.with_index do |article, index|
          used += GAP_PX unless index.zero?
          used += (title_lines(article) * TITLE_LINE_PX) + DATE_BLOCK_PX
          # However long it is, the newest headline is always shown -- an empty
          # slide is worse than a full one.
          index.zero? || used <= LIST_HEIGHT_PX
        end
      end

      def title_lines(article)
        [ (article.title.to_s.length / CHARS_PER_LINE.to_f).ceil, 1 ].max
      end
    end
  end
end
