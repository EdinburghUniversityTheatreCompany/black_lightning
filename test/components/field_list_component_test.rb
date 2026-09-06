require "test_helper"

class FieldListComponentTest < ViewComponent::TestCase
  # A nil hides the field. Showing a placeholder is the caller's job, where it
  # builds the spec.
  test "a nil value hides its field entirely" do
    render_inline(FieldListComponent.new(fields: { name: "Hamlet", venue: nil }))

    assert_text "Hamlet"
    assert_no_text "Venue"
  end

  test "symbol labels are titleised, string labels are left alone" do
    render_inline(FieldListComponent.new(fields: { start_date: "today", "MY Label" => "x" }))

    assert_text "Start Date:"
    assert_text "MY Label:"
  end

  test "booleans read as words rather than true and false" do
    render_inline(FieldListComponent.new(fields: { public: true, cancelled: false }))

    assert_no_text "true"
    assert_no_text "false"
  end

  test "a markdown field gets a heading and rendered markdown" do
    render_inline(FieldListComponent.new(fields: { blurb: { type: "markdown", markdown: "**bold**" } }))

    assert_selector "h3", text: "Blurb"
    assert_selector "strong", text: "bold"
  end

  test "a content field can supply its own header, or none" do
    render_inline(FieldListComponent.new(fields: { extra: { type: "content", header: "Custom", content: "body" } }))
    assert_selector "h3", text: "Custom"

    render_inline(FieldListComponent.new(fields: { extra: { type: "content", content: "body" } }))
    assert_no_selector "h3"
  end

  test "a real attachment renders, and offers the original only on the admin site" do
    picture = FactoryBot.create(:picture)
    field = { poster: { type: "image", image: picture.image, variant: helper_thumb } }

    render_inline(FieldListComponent.new(fields: field))
    assert_no_text "Download original image"

    render_inline(FieldListComponent.new(fields: field, admin_site: true))
    assert_text "Download original image"
  end

  # A record carrying only a generated placeholder has no image worth showing.
  test "a placeholder attachment counts as no image" do
    event = FactoryBot.create(:show)
    event.fetch_image

    render_inline(FieldListComponent.new(fields: { poster: { type: "image", image: event.image, variant: helper_thumb } }))

    assert_text "No Image"
    assert_no_selector "img"
  end

  private

  def helper_thumb = ApplicationController.helpers.thumb_variant
end
