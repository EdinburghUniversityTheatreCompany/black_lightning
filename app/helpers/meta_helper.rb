##
# =Metadata
#
# The <tt>@meta</tt> hash is seeded by ApplicationController#set_globals and rendered by
# #meta_tags. Anything derived from <tt>@title</tt> (<tt><title></tt>, og:title, twitter:title)
# is computed here, at render time: #set_globals is a +before_action+, so it runs before the
# action assigns @title and would read nil.
#
# For an example, see the shows controller.
##
module MetaHelper
  SITE_NAME = "Bedlam Theatre".freeze

  # Google truncates around 155-160 characters; show pages assign ~900 of publicity text.
  DESCRIPTION_LIMIT = 155

  # Params that identify a distinct page. Everything else, Ransack's q[...] above all, collapses
  # onto the unfiltered URL so the unbounded filter space cannot compete with the page it filters.
  CANONICAL_PARAMS = %w[page].freeze

  def page_title
    @title.present? ? "#{@title} | #{SITE_NAME}" : SITE_NAME
  end

  # The absolute URL this page wants to be indexed as.
  def canonical_url
    return @canonical_url if @canonical_url.present?

    # page=1 is dropped: kept, the canonical would create the duplicate it exists to collapse.
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

    safe_join(meta.flat_map { |name, content| Array(content).map { |item| meta_tag(name, item) } }, "\n")
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
    # og:image may be an array (banner plus production photos); the card takes the first.
    meta["twitter:image"]       ||= Array(meta["og:image"]).first

    meta.compact!
  end

  def truncate_description(description)
    return description if description.blank?

    description.to_s.squish.truncate(DESCRIPTION_LIMIT, separator: " ", omission: "…")
  end

  def meta_tag(name, content)
    type = name.start_with?("og", "fb") ? "property" : "name"

    # The names are this helper's own keys and the content is escaped, so the tag is safe.
    "<meta #{type}='#{name}' content='#{ERB::Util.html_escape content}' />".html_safe # rubocop:disable Rails/OutputSafety
  end
end
