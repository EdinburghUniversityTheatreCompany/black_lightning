module Display
  module Panels
    class News < Base
      # The slide is read from across a room in about twelve seconds, so the list
      # is bounded by the space it has rather than by a count. Headlines are set
      # at one constant size and taken until that space runs out, which means a
      # newsletter title long enough to wrap crowds out the ones below it. That
      # is the deliberate trade: the alternative is an ellipsis through a
      # headline, and a half-read headline tells you less than no headline.
      MAX_ITEMS = 5
      MAX_LINES = 8
      CHARS_PER_LINE = 55

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
        lines = 0

        candidates.take_while.with_index do |article, index|
          lines += title_lines(article)
          # However long it is, the newest headline is always shown -- an empty
          # slide is worse than a full one.
          index.zero? || lines <= MAX_LINES
        end
      end

      def title_lines(article)
        [ (article.title.to_s.length / CHARS_PER_LINE.to_f).ceil, 1 ].max
      end
    end
  end
end
