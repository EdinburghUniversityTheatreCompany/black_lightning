require "test_helper"

class MetaHelperTest < ActionView::TestCase
  # og:title is derived at render time: a before_action runs before the action assigns @title.
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

  test "explicit values in the hash win" do
    @title = "Ignored"

    tags = meta_tags({ "og:title" => "Explicit", "og:type" => "article" })

    assert_includes tags, "property='og:title' content='Explicit'"
    assert_includes tags, "property='og:type' content='article'"
  end

  test "meta tags carry og:type, og:site_name and a large-image twitter card" do
    tags = meta_tags({ description: "A show." })

    assert_includes tags, "property='og:type' content='website'"
    assert_includes tags, "property='og:site_name' content='Bedlam Theatre'"
    assert_includes tags, "name='twitter:card' content='summary_large_image'"
  end

  test "the twitter image follows the first og:image, which may be an array" do
    tags = meta_tags({ "og:image" => [ "https://example.com/a.png", "https://example.com/b.png" ] })

    assert_includes tags, "name='twitter:image' content='https://example.com/a.png'"
  end

  # Show pages assign the whole publicity text (~900 characters, newlines included).
  test "a long description is truncated on a word boundary, and og and twitter follow it" do
    tags = meta_tags({ description: "word " * 200 })

    described = tags.scan(/content='(word[^']*)'/).flatten
    assert_equal 3, described.length, "expected description, og:description and twitter:description"
    assert_equal 1, described.uniq.length, "all three should carry the same truncated text"
    assert_operator described.first.length, :<=, MetaHelper::DESCRIPTION_LIMIT
    assert described.first.end_with?("…"), "expected an ellipsis, got #{described.first.inspect}"
    assert_not described.first.include?("wor…"), "expected truncation on a word boundary"
  end

  test "a short description is left alone" do
    assert_includes meta_tags({ description: "Short and sweet." }), "content='Short and sweet.'"
  end

  test "newlines and runs of whitespace are collapsed out of the description" do
    tags = meta_tags({ description: "One line.\n\nAnother   line." })

    assert_includes tags, "content='One line. Another line.'"
  end

  test "description content is html escaped" do
    assert_includes meta_tags({ description: "Brad & Janet's <night>" }), "Brad &amp; Janet&#39;s &lt;night&gt;"
  end

  test "a nil meta hash still produces the defaults" do
    assert_includes meta_tags(nil), "property='og:site_name'"
  end
end
