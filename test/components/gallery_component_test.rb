require "test_helper"

class GalleryComponentTest < ViewComponent::TestCase
  def picture_with_tag
    picture = FactoryBot.create(:picture)
    picture.picture_tags << FactoryBot.create(:picture_tag, name: "Dress Rehearsal")
    Picture.where(id: picture.id)
  end

  test "renders nothing for an empty set" do
    render_inline(GalleryComponent.new(pictures: Picture.none))

    assert_no_selector "[data-controller='fancybox']"
  end

  test "header size is configurable" do
    render_inline(GalleryComponent.new(pictures: picture_with_tag, header_size: 4))

    assert_selector "h4", text: "Gallery"
  end

  # The two surfaces differ only here: admin screens list each picture's tags,
  # the public show pages do not.
  test "omits picture tags by default" do
    render_inline(GalleryComponent.new(pictures: picture_with_tag))

    assert_no_text "Dress Rehearsal"
  end

  test "lists picture tags when show_tags is set" do
    render_inline(GalleryComponent.new(pictures: picture_with_tag, show_tags: true))

    assert_selector "a", text: "Dress Rehearsal"
  end
end
