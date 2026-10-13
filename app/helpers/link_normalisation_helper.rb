# Fixes two link mistakes an editor can make at any time, where the links are rendered:
# a target typed without a scheme ("theimproverts.co.uk" is a relative path to a browser), and a
# link to our own www. host (which redirects to the apex on every hit).
module LinkNormalisationHelper
  CANONICAL_HOST = "bedlamtheatre.co.uk".freeze

  ABSOLUTE_PREFIXES = %w[/ # ? mailto: tel:].freeze

  # A dotted host with no scheme. Deliberately narrow: "about/committee" must stay relative.
  SCHEMELESS_HOST = %r{\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?:[/?#].*)?\z}i

  # "index.html" looks like a host to the pattern above; a relative file is far likelier.
  FILE_EXTENSIONS = %w[
    html htm php aspx asp jsp cgi
    pdf txt xml json csv rss atom
    jpg jpeg png gif svg webp ico
    css js map zip doc docx xls xlsx ppt pptx mp3 mp4
  ].freeze

  # +relativise+ is false outside a browser on our own origin, an email above all: a relative
  # href has no base URL there and is dead. The schemeless fix still applies.
  def normalise_link_target(href, relativise: true)
    return href if href.blank?

    href = href.strip

    return relativise ? relativise_own_host(href) : href if href.start_with?("http://", "https://")
    return href if ABSOLUTE_PREFIXES.any? { |prefix| href.start_with?(prefix) }
    return "https://#{href}" if href.match?(SCHEMELESS_HOST) && !bare_filename?(href)

    href
  end

  private

  # A link to our own site becomes a path, so it never spends a redirect. An autolinked bare URL
  # keeps its visible text but gets the path as its href, which is deliberate.
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

  # A dotted name with no path, ending in a file extension.
  def bare_filename?(href)
    return false if href.include?("/")

    FILE_EXTENSIONS.include?(href.split(".").last.to_s.downcase)
  end

  def own_host?(host) = host.to_s.downcase.delete_prefix("www.") == CANONICAL_HOST
end
