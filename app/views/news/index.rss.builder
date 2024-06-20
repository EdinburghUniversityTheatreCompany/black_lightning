#with thanks to http://techoctave.com/c7/posts/32-create-an-rss-feed-in-rails

xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    xml.title "Bedlam Theatre"
    xml.description "Public news RSS feed."
    xml.link news_index_url

    for news in @news
      xml.item do
        xml.title news.title
        xml.description render_markdown(news.body)
        xml.pubDate news.created_at.to_s
        xml.link news_url(news)
        xml.guid news_url(news)
      end
    end
  end
end