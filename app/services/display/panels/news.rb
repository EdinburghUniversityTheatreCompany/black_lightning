module Display
  module Panels
    class News < Base
      def available?
        article.present?
      end

      def partial
        "display/panels/news"
      end

      def locals
        { article: article }
      end

      private

      # News carries default_scope -> { order("publish_date DESC") }, so first
      # is the most recent.
      def article
        return @article if defined?(@article)

        @article = ::News.where(show_public: true).current.first
      end
    end
  end
end
