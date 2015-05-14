# see http://stackoverflow.com/questions/5460862/caching-twitter-api-calls-in-rails
module TwitterHelper
  def twitter_timeline
    client = Twitter::REST::Client.new do |config|
      config.consumer_key = Rails.application.secrets.twitter['consumer_key']
      config.consumer_secret = Rails.application.secrets.twitter['consumer_secret']
      config.access_token = Rails.application.secrets.twitter['access_token']
      config.access_token_secret = Rails.application.secrets.twitter['access_token_secret']
    end

    Rails.cache.fetch('bedlam_tweets', expires_in: 5.minutes) do
      begin
        # Note the Twitter API applies the 'count' filter before any other filters,
        # therefore, the below may return anything between 0 and 10 tweets.
        tweets = client.user_timeline('bedlamtheatre', count: 10, exclude_replies: true)

        tweets = tweets[0..2]
      rescue => e
        return [Twitter::Tweet.new(id: -1, text: "Error fetching tweets: #{e.message}")]
      end
    end
  end

  def auto_link_tweet(tweet)
    html = tweet.text
    html = html.gsub(/@(?<user>.+?\b)/, "<a href=\"http://twitter.com/\\k<user>\">@\\k<user></a>")
    html = html.gsub(/(?<tag>#.+?\b)/, "<a href=\"http://twitter.com/\\k<tag>\">\\k<tag></a>")
    html = auto_link(html)
    return html
  end
end
