require "test_helper"

class LinkNormalisationHelperTest < ActionView::TestCase
  include LinkNormalisationHelper

  UNCHANGED = [
    "about/committee", "/shows", "#section",
    "index.html", "programme.pdf", # a file, not a host
    "mailto:it@bedlamtheatre.co.uk", "tel:+441312255705",
    "https://wiki.bedlamtheatre.co.uk/", "https://www.instagram.com/bedlam.archives/",
    "https://tickets.bedlamtheatre.co.uk/eutc/" # a subdomain of ours is external, not our own host
  ].freeze

  # Typed without a scheme these resolved against the site root and 404ed; each of our own www
  # links costs a 301 to the apex.
  REWRITTEN = {
    "theimproverts.co.uk" => "https://theimproverts.co.uk",
    "wiki.bedlamtheatre.co.uk/history" => "https://wiki.bedlamtheatre.co.uk/history",
    "www.example.com/page?a=1" => "https://www.example.com/page?a=1",
    "https://www.bedlamtheatre.co.uk/archives/events" => "/archives/events",
    "https://www.bedlamtheatre.co.uk/venues" => "/venues",
    "https://bedlamtheatre.co.uk/shows" => "/shows",
    "https://bedlamtheatre.co.uk" => "/",
    "https://www.bedlamtheatre.co.uk/shows?page=2#cast" => "/shows?page=2#cast"
  }.freeze

  test "paths, files, mailto, tel and other people's hosts are left alone" do
    UNCHANGED.each { |href| assert_equal href, normalise_link_target(href), href }
  end

  test "a bare domain becomes an external link and our own host becomes a path" do
    REWRITTEN.each { |href, expected| assert_equal expected, normalise_link_target(href), href }
  end

  test "blank input survives" do
    assert_nil normalise_link_target(nil)
    assert_equal "", normalise_link_target("")
  end
end

# The renderer wiring: a schemeless link in DB content must not reach the page as a relative path.
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
end
