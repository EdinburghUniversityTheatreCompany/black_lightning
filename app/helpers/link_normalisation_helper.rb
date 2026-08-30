##
# Two link bugs that a content editor can reintroduce at any time, so they are fixed where the
# links are rendered rather than one row at a time.
#
# 1. A link target typed without a scheme -- "theimproverts.co.uk", "www.example.com/x" -- is a
#    relative path to a browser, so it resolved against the site root. The live site had
#    /get_involved/theimproverts.co.uk and /https:/wiki.bedlamtheatre.co.uk/history both 404ing.
#
# 2. A link written against our own www. host redirects to the apex on every hit. Two of those
#    sat in the navbar, on every page of the site.
##
module LinkNormalisationHelper
  CANONICAL_HOST = "bedlamtheatre.co.uk".freeze

  # Schemes and shapes that are already unambiguous to a browser.
  ABSOLUTE_PREFIXES = %w[/ # ? mailto: tel: http:// https:// //].freeze

  # "theimproverts.co.uk", "www.example.com/page" -- a dot-separated label before any slash, and
  # no scheme. Deliberately narrow: "about/committee" must stay relative.
  SCHEMELESS_HOST = %r{\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?:[/?#].*)?\z}i

  # "index.html" is a dot-separated label with no scheme too, so the pattern above cannot tell it
  # from a hostname. A relative file is far likelier than a .html top-level domain.
  FILE_EXTENSIONS = %w[
    html htm php aspx asp jsp cgi
    pdf txt xml json csv rss atom
    jpg jpeg png gif svg webp ico
    css js map zip doc docx xls xlsx ppt pptx mp3 mp4
  ].freeze

  ##
  # Turns a link target into one that resolves where its author meant it to.
  #
  # +relativise+ is false wherever the markup will be read outside a browser on our own origin --
  # an email above all, where a relative href has no base URL to resolve against and is simply
  # dead. The schemeless fix still applies there: a target typed without a scheme is broken in an
  # email too.
  ##
  def normalise_link_target(href, relativise: true)
    return href if href.blank?

    href = href.strip

    return relativise ? relativise_own_host(href) : href if href.start_with?("http://", "https://")
    return href if ABSOLUTE_PREFIXES.any? { |prefix| href.start_with?(prefix) }
    return "https://#{href}" if href.match?(SCHEMELESS_HOST) && !bare_filename?(href)

    href
  end

  private

  ##
  # A link to our own site becomes a path, so it never spends a redirect -- and www. never
  # competes with the apex.
  #
  # This also rewrites an autolinked bare URL, leaving markup whose visible text still reads
  # "https://www.bedlamtheatre.co.uk" while its href is "/". That is deliberate: the destination
  # is identical and the redirect is what we came to remove.
  ##
  def relativise_own_host(href)
    uri = URI.parse(href)

    return href unless own_host?(uri.host)

    path = uri.path.presence || "/"
    path += "?#{uri.query}" if uri.query.present?
    path += "##{uri.fragment}" if uri.fragment.present?
    path
  rescue URI::InvalidURIError
    href
  end

  ##
  # A dotted name with no path at all, ending in something that reads as a file extension.
  ##
  def bare_filename?(href)
    return false if href.include?("/")

    FILE_EXTENSIONS.include?(href.split(".").last.to_s.downcase)
  end

  def own_host?(host)
    return false if host.blank?

    host = host.downcase.delete_prefix("www.")

    host == CANONICAL_HOST
  end
end
