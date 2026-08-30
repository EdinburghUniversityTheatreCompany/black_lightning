require "test_helper"

class LinkNormalisationHelperTest < ActionView::TestCase
  include LinkNormalisationHelper

  # The live site 404ed on /get_involved/theimproverts.co.uk and
  # /https:/wiki.bedlamtheatre.co.uk/history -- both a link target typed without a scheme.
  test "a bare domain becomes an absolute external link" do
    assert_equal "https://theimproverts.co.uk", normalise_link_target("theimproverts.co.uk")
    assert_equal "https://wiki.bedlamtheatre.co.uk/history", normalise_link_target("wiki.bedlamtheatre.co.uk/history")
    assert_equal "https://www.example.com/page?a=1", normalise_link_target("www.example.com/page?a=1")
  end

  test "a relative path is left alone" do
    assert_equal "about/committee", normalise_link_target("about/committee")
    assert_equal "/shows", normalise_link_target("/shows")
    assert_equal "#section", normalise_link_target("#section")
  end

  # "index.html" has a dot and no scheme but is plainly a file, not a host.
  test "a filename is not mistaken for a domain" do
    assert_equal "index.html", normalise_link_target("index.html")
    assert_equal "programme.pdf", normalise_link_target("programme.pdf")
  end

  test "mailto and tel are left alone" do
    assert_equal "mailto:it@bedlamtheatre.co.uk", normalise_link_target("mailto:it@bedlamtheatre.co.uk")
    assert_equal "tel:+441312255705", normalise_link_target("tel:+441312255705")
  end

  # Two of these sat in the navbar, so every page on the site carried two needless 301s.
  test "a link to our own www host becomes a path" do
    assert_equal "/archives/events", normalise_link_target("https://www.bedlamtheatre.co.uk/archives/events")
    assert_equal "/venues", normalise_link_target("https://www.bedlamtheatre.co.uk/venues")
  end

  test "a link to our own apex host also becomes a path" do
    assert_equal "/shows", normalise_link_target("https://bedlamtheatre.co.uk/shows")
    assert_equal "/", normalise_link_target("https://bedlamtheatre.co.uk")
  end

  test "query and fragment survive relativising" do
    assert_equal "/shows?page=2#cast", normalise_link_target("https://www.bedlamtheatre.co.uk/shows?page=2#cast")
  end

  test "a genuinely external absolute link is untouched" do
    assert_equal "https://wiki.bedlamtheatre.co.uk/", normalise_link_target("https://wiki.bedlamtheatre.co.uk/")
    assert_equal "https://www.instagram.com/bedlam.archives/", normalise_link_target("https://www.instagram.com/bedlam.archives/")
  end

  test "a subdomain of ours is external, not our own host" do
    assert_equal "https://tickets.bedlamtheatre.co.uk/eutc/", normalise_link_target("https://tickets.bedlamtheatre.co.uk/eutc/")
  end

  test "blank input survives" do
    assert_nil normalise_link_target(nil)
    assert_equal "", normalise_link_target("")
  end
end

# The renderers that consume the normalisation, so a schemeless link in DB content cannot reach
# the page as a relative path again.
class MarkdownLinkNormalisationTest < ActionView::TestCase
  include MdHelper

  test "a schemeless markdown link renders as an external link" do
    html = render_markdown("Visit [the Improverts](theimproverts.co.uk) tonight.")

    assert_includes html, 'href="https://theimproverts.co.uk"'
  end

  test "a markdown link to our own www host renders as a path" do
    html = render_markdown("See the [events archive](https://www.bedlamtheatre.co.uk/archives/events).")

    assert_includes html, 'href="/archives/events"'
  end

  test "an ordinary relative markdown link is untouched" do
    html = render_markdown("Read the [privacy policy](/privacy_policy).")

    assert_includes html, 'href="/privacy_policy"'
  end

  test "an external markdown link keeps its host" do
    html = render_markdown("Our [wiki](https://wiki.bedlamtheatre.co.uk/history) has more.")

    assert_includes html, 'href="https://wiki.bedlamtheatre.co.uk/history"'
  end
end
