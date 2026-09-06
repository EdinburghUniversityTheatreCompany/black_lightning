class ImageComponent < ViewComponent::Base
  # full_width is a styling decision, priority a performance one. They were one
  # flag once and the performance half was backwards, costing a measured 1552ms
  # of homepage LCP; loading stays unset unless priority is passed, so it falls
  # through to config.action_view.image_loading.
  def initialize(image:, variant: nil, full_width: true, priority: false, alt: nil,
                 srcset_variants: nil, image_options: {}, proxy: false)
    @image = image
    @variant = variant
    @full_width = full_width
    @priority = priority
    @alt = alt
    @srcset_variants = srcset_variants
    @image_options = image_options
    @proxy = proxy
  end

  def before_render
    warn_or_raise_without_variant if @variant.nil?
  end

  private

  def warn_or_raise_without_variant
    if Rails.env.local?
      raise ArgumentError,
            "ImageComponent rendered without a variant — this serves the full-size blob. " \
            "Pass variant:, or use image_tag directly if you intentionally want full size."
    end

    Rails.logger.warn(
      "[ImageComponent] rendered without variant for blob #{@image.try(:blob)&.id} — " \
      "serving full-size. Fix the caller."
    )
  end

  def source
    resolved = @variant.present? ? @image.variant(@variant) : @image
    @proxy ? helpers.active_storage_proxy_url(resolved) : resolved
  end

  # Always an alt attribute. Every image on the site was missing one entirely, a
  # WCAG 2.2 1.1.1 failure; an explicit empty alt at least marks an image as
  # decorative, which is right for the ones a caption already covers. Passed from
  # the template rather than merged in here so it is visible at the img tag.
  def alt_text
    @alt.to_s
  end

  def image_options
    options = @image_options.merge(dimensions)
    options = options.merge(class: "w-full h-auto #{options[:class]}") if @full_width
    options = options.merge(loading: "eager", fetchpriority: "high") if @priority
    options = options.merge(srcset_options(options)) if srcset?
    options
  end

  def dimensions
    if @variant.present?
      helpers.variant_width_and_height_html(@variant)
    else
      helpers.base_width_and_height_html(@image)
    end
  end

  # A phone downloading a 960px card into a 412px viewport is roughly 2.3x the
  # pixels it can show. Offering the smaller variants that already exist lets the
  # browser pick; the URLs have to be proxied ones, so this needs proxy.
  def srcset?
    @srcset_variants.present? && @proxy
  end

  def srcset_options(options)
    candidates = @srcset_variants.map do |v|
      "#{helpers.active_storage_proxy_url(@image.variant(v))} #{v[:resize_to_fill][0]}w"
    end

    { srcset: candidates.join(", "), sizes: options.delete(:sizes) || "(max-width: 768px) 100vw, 33vw" }
  end
end
