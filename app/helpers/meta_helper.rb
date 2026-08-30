##
# =Metadata
#
# The <tt>@meta</tt> hash is seeded by ApplicationController#set_globals and rendered by
# #meta_tags. Set <tt>@title</tt> in the controller (preferred) or the view; everything that
# reads from it -- the <tt><title></tt>, <tt>og:title</tt>, <tt>twitter:title</tt> -- is derived
# here, at render time.
#
# That timing is the point: #set_globals is a +before_action+, so it runs before the action
# assigns <tt>@title</tt>. Anything derived from @title there reads nil.
#
# For an example, see the shows controller.
##
module MetaHelper
  SITE_NAME = "Bedlam Theatre".freeze

  # Google truncates around 155-160 characters. Show pages assign the whole publicity text,
  # which runs to ~900.
  DESCRIPTION_LIMIT = 155

  # Query parameters that identify a distinct page rather than a filtered view of one.
  # Everything else -- Ransack's q[...] especially -- collapses onto the unfiltered URL, so the
  # unbounded author/company/venue filter space cannot compete with the page it filters.
  CANONICAL_PARAMS = %w[page].freeze

  ##
  # The contents of the <title> tag.
  ##
  def page_title
    @title.present? ? "#{@title} | #{SITE_NAME}" : SITE_NAME
  end

  ##
  # The absolute URL this page wants to be indexed as.
  ##
  def canonical_url
    return @canonical_url if @canonical_url.present?

    # page=1 is the same content as no page at all, so it must canonicalise to the same URL --
    # otherwise the canonical tag introduces the duplicate it exists to collapse.
    kept = request.query_parameters.slice(*CANONICAL_PARAMS).reject { |_, value| value.to_s == "1" }
    base = request.base_url + request.path

    kept.any? ? "#{base}?#{kept.to_query}" : base
  end

  ##
  # Creates the meta data tags.
  ##
  def meta_tags(meta)
    meta = (meta || {}).transform_keys(&:to_s)

    apply_defaults(meta)

    meta.flat_map { |name, content| Array(content).map { |item| meta_tag(name, item) } }.join("\n")
  end

  private

  def apply_defaults(meta)
    meta["description"] = truncate_description(meta["description"]) if meta.key?("description")

    meta["og:title"]       ||= @title.presence || SITE_NAME
    meta["og:description"] ||= meta["description"]
    meta["og:type"]        ||= "website"
    meta["og:site_name"]   ||= SITE_NAME
    meta["og:url"]         ||= canonical_url

    meta["twitter:card"]        ||= "summary_large_image"
    meta["twitter:title"]       ||= meta["og:title"]
    meta["twitter:description"] ||= meta["og:description"]
    # og:image may be an array (a show carries its banner plus every production photo); the card
    # takes one image, so it takes the first, which is the one the page led with.
    meta["twitter:image"]       ||= Array(meta["og:image"]).first

    meta.compact!
  end

  def truncate_description(description)
    return description if description.blank?

    description.to_s.squish.truncate(DESCRIPTION_LIMIT, separator: " ", omission: "…")
  end

  def meta_tag(name, content)
    type = name.start_with?("og", "fb") ? "property" : "name"

    "<meta #{type}='#{name}' content='#{ERB::Util.html_escape content}' />"
  end
end
