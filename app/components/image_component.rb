class ImageComponent < ViewComponent::Base
  # full_width is styling, priority is loading: only an LCP element passes priority. Loading
  # stays unset otherwise, so it falls through to config.action_view.image_loading.
  def initialize(image:, variant: nil, full_width: true, priority: false, alt: nil,
                 srcset_variants: nil, image_options: {}, proxy: false)
    @image = image
    @variant = variant
    @full_width = full_width
    @priority = priority
    @alt_text = alt.to_s # Always emitted (WCAG 1.1.1); empty marks the image decorative.
    @srcset_variants = srcset_variants
    @image_options = image_options
    @proxy = proxy
  end

  def before_render
    warn_or_raise_without_variant if @variant.nil?
  end

  private

  attr_reader :alt_text

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

  def image_options
    options = @image_options.merge(dimensions)
    options = options.merge(class: "w-full h-auto #{options[:class]}") if @full_width
    options = options.merge(loading: "eager", fetchpriority: "high") if @priority
    options = options.merge(srcset_options) if srcset?
    options
  end

  def dimensions
    if @variant.present?
      helpers.variant_width_and_height_html(@variant)
    else
      helpers.base_width_and_height_html(@image)
    end
  end

  # Lets the browser pick a smaller variant on a phone. Needs proxy: srcset URLs must be proxied.
  def srcset?
    @srcset_variants.present? && @proxy
  end

  def srcset_options
    candidates = @srcset_variants.map do |v|
      "#{helpers.active_storage_proxy_url(@image.variant(v))} #{v[:resize_to_fill][0]}w"
    end

    { srcset: candidates.join(", "), sizes: "(max-width: 768px) 100vw, 33vw" }
  end
end
