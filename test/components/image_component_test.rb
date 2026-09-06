require "test_helper"

class ImageComponentTest < ViewComponent::TestCase
  def image
    @image ||= FactoryBot.create(:picture).image
  end

  def thumb  = ApplicationController.helpers.thumb_variant
  def medium = ApplicationController.helpers.medium_variant

  # Serving the full-size blob is almost always a caller's mistake, so it is loud
  # in development and test and only a warning in production.
  test "refuses to render without a variant in a local environment" do
    assert_raises(ArgumentError) do
      render_inline(ImageComponent.new(image: image))
    end
  end

  # WCAG 2.2 1.1.1: an explicit empty alt still marks an image as decorative,
  # where a missing attribute says nothing at all.
  test "always emits an alt attribute, empty when none is given" do
    render_inline(ImageComponent.new(image: image, variant: thumb))

    assert_selector "img[alt='']"
  end

  test "renders the alt it is given" do
    render_inline(ImageComponent.new(image: image, variant: thumb, alt: "A poster"))

    assert_selector "img[alt='A poster']"
  end

  # full_width is styling, priority is loading. They were one flag once, with the
  # performance half backwards.
  test "leaves loading unset unless it is the priority image" do
    render_inline(ImageComponent.new(image: image, variant: thumb))

    assert_no_selector "img[loading='eager']"
    assert_no_selector "img[fetchpriority]"
  end

  test "the priority image loads eagerly at high fetch priority" do
    render_inline(ImageComponent.new(image: image, variant: thumb, priority: true))

    assert_selector "img[loading='eager'][fetchpriority='high']"
  end

  test "full_width adds the sizing classes and keeps the caller's own" do
    render_inline(ImageComponent.new(image: image, variant: thumb, image_options: { class: "rounded-t" }))

    assert_selector "img.w-full.h-auto.rounded-t"
  end

  test "full_width can be turned off" do
    render_inline(ImageComponent.new(image: image, variant: thumb, full_width: false))

    assert_no_selector "img.w-full"
  end

  # srcset needs proxied URLs, so it is only offered when proxy is on.
  test "offers a srcset when given variants to proxy" do
    render_inline(ImageComponent.new(image: image, variant: medium, proxy: true,
                                     srcset_variants: [ thumb, medium ]))

    assert_selector "img[srcset][sizes]"
  end

  test "emits no srcset without proxy, since the URLs would not be proxied" do
    render_inline(ImageComponent.new(image: image, variant: medium,
                                     srcset_variants: [ thumb, medium ]))

    assert_no_selector "img[srcset]"
  end
end
