require "test_helper"

class MdHelperTest < ActionView::TestCase
  setup do
    @markdown = <<~MARKDOWN
      kramdown
      ========

      Most text entered into the Bedlam Admin site will be rendered using kramdown.

      kramdown is an increadibly powerful, yet very natrual markup language.

      More details about kramdown can be found [here](http://kramdown.rubyforge.org/syntax.html#links-and-images).
    MARKDOWN
  end

  test "render markdown basic structure" do
    assert_equal "", render_markdown(nil)
    html = render_markdown(@markdown)
    assert_includes html, "<h1"
    assert_includes html, "kramdown"
    assert_includes html, "<p>"
    assert_includes html, "<a href="
  end

  test "render plain" do
    assert_equal "", render_plain(nil)
    result = render_plain(@markdown)
    assert_includes result, "kramdown"
    assert_includes result, "Bedlam Admin"
  end

  test "render_plain decodes HTML entities" do
    assert_includes render_plain("John & Jeremy"), "John & Jeremy"
    assert_includes render_plain("Tom & Jerry"), "Tom & Jerry"
    assert_not_includes render_plain("Tom & Jerry"), "&amp;"
  end

  test "truncate_markdown does not double-encode HTML entities" do
    text = "John & Jeremy's father (lovingly, Pops) owned a bar. Now, with him having 'kicked the keg' if you will, one of them has to run it."
    result = truncate_markdown(text, 120)
    assert_not_includes result, "&amp;amp;", "HTML entities should not be double-encoded"
  end

  test "truncated markdown" do
    archive_warning = '<i class="icon-info-sign icon-large"></i> This show was imported from the old website. If you are able to provide any more information, please contact the [Archivist](mailto:archive@bedlamtheatre.co.uk). {:.alert .alert-info}'
    expected_truncated_description = "This show was imported from the old website. If you are a..."
    assert_equal expected_truncated_description, truncate_markdown(archive_warning, 60)

    # CommonMark treats <!-- ... --> as an HTML block — the entire line is suppressed (unsafe: false)
    description_with_comment = "<!-- it happened 2 years before 1980, idk when exactly -->\nPineapple"
    assert_equal "Pineapple", truncate_markdown(description_with_comment)
  end

  test "render_markdown sanitizes script tags" do
    result = render_markdown("<script>alert(1)</script>")
    assert_not_includes result, "<script"
  end

  test "render_markdown strips javascript: scheme from links" do
    result = render_markdown("[click me](javascript:alert(1))")
    assert_not_includes result, "javascript:"
  end

  test "render_markdown preserves legitimate markdown" do
    markdown = "**bold** and [link](http://example.com)"
    result = render_markdown(markdown)
    assert_includes result, "<strong>bold</strong>"
    assert_includes result, '<a href="http://example.com">link</a>'
  end

  test "render_markdown preserves legitimate images" do
    result = render_markdown("![alt text](/images/test.png)")
    assert_includes result, '<img src="/images/test.png"'
    assert_includes result, 'alt="alt text"'
  end

  test "render_markdown preserves legitimate tables" do
    markdown = "| Header |\n|--------|\n| Cell   |"
    result = render_markdown(markdown)
    assert_includes result, "<table>"
    assert_includes result, "<tbody>"
    assert_includes result, "Header"
  end

  test "IAL block syntax applies class to previous element" do
    markdown = "Some text\n\n{ .card-body }"
    result = render_markdown(markdown)
    assert_includes result, 'class="card-body"'
    assert_not_includes result, "{ .card-body }"
  end

  test "IAL inline syntax applies class to same element" do
    result = render_markdown("## My Heading { .text-danger }")
    assert_includes result, 'class="text-danger"'
    assert_includes result, "My Heading"
    assert_not_includes result, "{ .text-danger }"
  end

  test "IAL supports multiple classes" do
    result = render_markdown("A paragraph { .lead .text-muted }")
    assert_includes result, "lead"
    assert_includes result, "text-muted"
    assert_not_includes result, "{ .lead .text-muted }"
  end

  test "IAL supports id token" do
    result = render_markdown("## Heading { #my-anchor }")
    assert_includes result, 'id="my-anchor"'
    assert_not_includes result, "{ #my-anchor }"
  end

  test "IAL block syntax without previous element is ignored safely" do
    result = render_markdown("{ .orphan }")
    assert_not_includes result, "{ .orphan }"
  end

  test "IAL immediately after inline element applies to that element" do
    result = render_markdown("[This is a link](https://bedlamfringe.co.uk){ .card-body }")
    assert_match(/<a[^>]*class="card-body"[^>]*>/, result)
    assert_not_includes result, "{ .card-body }"
  end

  test "IAL immediately after image applies to the img element" do
    result = render_markdown("![alt text](/images/test.png){ .rounded .img-fluid }")
    assert_match(/<img[^>]*class="rounded img-fluid"[^>]*>/, result)
    assert_not_includes result, "{ .rounded .img-fluid }"
  end
end
