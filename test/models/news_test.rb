# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text(65535)</tt>
# *slug*::               <tt>string(255)</tt>
# *publish_date*::       <tt>datetime</tt>
# *show_public*::        <tt>boolean</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *author_id*::          <tt>integer</tt>
#--
# == Schema Information End
#++
require "test_helper"

class NewsTest < ActionView::TestCase
  test "preview" do
    news = News.new

    wisdom = "The world is like a pineapple. Very tough to get inside and it tries to eat you."
    news.body = wisdom
    assert_equal wisdom, news.preview

    news.body = "#{wisdom}#{wisdom}\n#{wisdom}"
    assert_equal "#{wisdom}#{wisdom}", news.preview

    news.body = "#{wisdom}</p>#{wisdom}</p>#{wisdom}"
    assert_equal "#{wisdom}</p>#{wisdom}", news.preview

    news.body = ""
    assert_equal "", news.preview

    news.body = nil
    assert_equal "", news.preview
  end

  test "automatically generates slug from title if blank" do
    news = FactoryBot.build(:news, title: "Test News Title", slug: "")
    assert news.valid?
    assert_equal "test-news-title", news.slug
  end

  test "updates slug when title changes and slug was auto-generated" do
    news = FactoryBot.create(:news, title: "Original Title")
    original_slug = news.slug

    news.title = "New News Title"
    news.valid?
    assert_not_equal original_slug, news.slug
    assert_equal "new-news-title", news.slug
  end

  test "does not update slug when title changes if slug was manually set" do
    news = FactoryBot.create(:news, title: "Original Title", slug: "custom-slug")

    news.title = "New News Title"
    news.valid?
    assert_equal "custom-slug", news.slug
  end

  test "generates unique slugs when duplicates would occur" do
    news1 = FactoryBot.create(:news, title: "Test News")
    news2 = FactoryBot.build(:news, title: "Test News", slug: "")

    assert news2.valid?
    assert_equal "test-news", news1.slug
    assert_equal "test-news-1", news2.slug
  end

  test "handles special characters in slug generation" do
    news = FactoryBot.build(:news, title: 'News with "Quotes" & Symbols!', slug: "")
    assert news.valid?
    assert_equal "news-with-quotes-and-symbols", news.slug
  end

  test "handles accented characters in slug generation" do
    news = FactoryBot.build(:news, title: "Nouvelles spéciàles", slug: "")
    assert news.valid?
    assert_equal "nouvelles-speciales", news.slug
  end

  test "slug uniqueness validation works case-insensitively" do
    FactoryBot.create(:news, slug: "test-slug")
    duplicate_news = FactoryBot.build(:news, slug: "TEST-SLUG")

    assert_not duplicate_news.valid?
    assert duplicate_news.errors[:slug].any? { |error| error.include?("already taken") }
  end
end
