module Display
  module Panels
    class News
      # The list is bounded by the space it has, not a count: headlines are set at
      # one size and taken until the space runs out, so a title long enough to wrap
      # crowds out the ones below it. Deliberate: a half-read headline (ellipsis)
      # tells you less than none.
      MAX_ITEMS = 4

      # Pixels of the 1080-tall screen. Each figure is one Tailwind class in
      # _news.html.erb; change a class and re-measure, nothing checks these at runtime.
      #   1080 - py-16 (128) - the "Latest News" label and mb-10 (40 + 40)
      #   - the QR block and mt-8 (160 + 32) = 680.
      LIST_HEIGHT_PX = 680
      # text-5xl (48px) at leading-tight (1.25).
      TITLE_LINE_PX = 60
      # mt-3 (12px) plus the date's text-3xl line box (36px).
      DATE_BLOCK_PX = 48
      # gap-8, charged between items and not after the last one.
      GAP_PX = 32

      # Measured in Chrome across the list's 1728px at text-5xl bold: 76 characters
      # fit a line in mixed case, 66 in all caps. Too low is not a safe error: it
      # charges a headline for lines never drawn and drops the ones below it.
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

      # News's default_scope orders newest first.
      def articles
        @articles ||= fill_to_budget(::News.where(show_public: true).current.limit(MAX_ITEMS).to_a)
      end

      def fill_to_budget(candidates)
        used = 0

        candidates.take_while.with_index do |article, index|
          used += GAP_PX unless index.zero?
          used += (title_lines(article) * TITLE_LINE_PX) + DATE_BLOCK_PX
          # The newest headline always shows, however long: an empty slide is worse.
          index.zero? || used <= LIST_HEIGHT_PX
        end
      end

      def title_lines(article)
        [ (article.title.to_s.length / CHARS_PER_LINE.to_f).ceil, 1 ].max
      end
    end
  end
end
