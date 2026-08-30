require "test_helper"

class MetaHelperTest < ActionView::TestCase
  # og:title used to be derived in ApplicationController#set_globals, a before_action that runs
  # BEFORE the action assigns @title -- so it always read nil and every share was captioned
  # "Bedlam Theatre". These tests pin the derivation to render time.
  test "page title appends the site name when a title is set" do
    @title = "Richard O'Brien's The Rocky Horror Show"

    assert_equal "Richard O'Brien's The Rocky Horror Show | Bedlam Theatre", page_title
  end

  test "page title is the bare site name when no title is set" do
    assert_equal "Bedlam Theatre", page_title
  end

  test "og:title follows @title rather than the hash built before the action ran" do
    @title = "The History Boys"

    assert_includes meta_tags({}), "property='og:title' content='The History Boys'"
  end

  test "og:title falls back to the site name when the page has no title" do
    assert_includes meta_tags({}), "property='og:title' content='Bedlam Theatre'"
  end

  test "an explicit og:title in the hash still wins" do
    @title = "Ignored"

    assert_includes meta_tags({ "og:title" => "Explicit" }), "content='Explicit'"
  end

  test "meta tags carry og:type, og:site_name and a large-image twitter card" do
    tags = meta_tags({ description: "A show." })

    assert_includes tags, "property='og:type' content='website'"
    assert_includes tags, "property='og:site_name' content='Bedlam Theatre'"
    assert_includes tags, "name='twitter:card' content='summary_large_image'"
  end

  test "og:type can be overridden per page" do
    assert_includes meta_tags({ "og:type" => "article" }), "property='og:type' content='article'"
  end

  test "the twitter image follows the first og:image, which may be an array" do
    tags = meta_tags({ "og:image" => [ "https://example.com/a.png", "https://example.com/b.png" ] })

    assert_includes tags, "name='twitter:image' content='https://example.com/a.png'"
  end

  # Show pages assigned the whole publicity text: ~900 characters of it, newlines included.
  test "a long description is truncated on a word boundary" do
    long = "word " * 200
    tags = meta_tags({ description: long })

    content = tags[/name='description' content='(.*?)' \/>/m, 1]
    assert_operator content.length, :<=, MetaHelper::DESCRIPTION_LIMIT
    assert content.end_with?("…"), "expected an ellipsis, got #{content.inspect}"
    assert_not content.include?("wor…"), "expected truncation on a word boundary"
  end

  test "a short description is left alone" do
    assert_includes meta_tags({ description: "Short and sweet." }), "content='Short and sweet.'"
  end

  test "newlines and runs of whitespace are collapsed out of the description" do
    tags = meta_tags({ description: "One line.\n\nAnother   line." })

    assert_includes tags, "content='One line. Another line.'"
  end

  test "og:description follows the truncated description, not the raw one" do
    long = "word " * 200
    tags = meta_tags({ description: long })

    described = tags.scan(/content='(word[^']*)'/).flatten
    assert_equal 3, described.length, "expected description, og:description and twitter:description"
    assert_equal 1, described.uniq.length, "all three should carry the same truncated text"
    assert_operator described.first.length, :<=, MetaHelper::DESCRIPTION_LIMIT
  end

  test "description content is html escaped" do
    assert_includes meta_tags({ description: "Brad & Janet's <night>" }), "Brad &amp; Janet&#39;s &lt;night&gt;"
  end

  test "a nil meta hash still produces the defaults" do
    assert_includes meta_tags(nil), "property='og:site_name'"
  end
end
