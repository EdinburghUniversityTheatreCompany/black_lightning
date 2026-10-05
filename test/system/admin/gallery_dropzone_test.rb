require "application_system_test_case"

# The gallery uploader is the only user of the dropzone library, which no request test can reach:
# an upgrade like 5 to 6 could break every admin picture upload with nothing red to show.
class Admin::GalleryDropzoneTest < ApplicationSystemTestCase
  # DirectUploadController gives the hidden signed-id field this name, which proves the upload
  # reached the form rather than just the screen.
  FIELD_NAME = "dropzone_pictures[files][]".freeze

  setup do
    login_as users(:admin)
  end

  test "a file dropped on the gallery uploader is direct-uploaded and attached to the form" do
    show = FactoryBot.create(:show)
    visit edit_admin_show_url(show)

    assert_selector ".dropzone[data-controller='dropzone']"

    # The blob comes from the direct upload, so this separates a drawn preview from a received file.
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      drop_file("test.png", "image/png")
      assert_selector ".dz-preview.dz-success", wait: 15
    end

    # Two hidden fields carry this name: Rails' empty one for a `multiple` input, and the upload's.
    signed_ids = all("input[type='hidden'][name='#{FIELD_NAME}']", visible: :all)
                 .map(&:value).reject(&:blank?)

    assert_equal [ ActiveStorage::Blob.order(:id).last.signed_id ], signed_ids,
                 "the direct upload's signed id never reached the form"
  end

  test "the drop target is live rather than relying on the library's own discovery" do
    show = FactoryBot.create(:show)
    visit edit_admin_show_url(show)

    # Dropzone sets `element.dropzone` on attach. The dz-* classes are in the markup regardless,
    # so they prove nothing.
    assert page.evaluate_script(
      "!!document.querySelector('[data-controller=\"dropzone\"]').dropzone"
    ), "the dropzone widget was never constructed on the drop target"

    assert_no_selector "input[type='file'][name='#{FIELD_NAME}']", visible: true
  end

  private

    # attach_file would drive the disabled native input; Dropzone listens for a DataTransfer drop.
    def drop_file(filename, content_type)
      encoded = Base64.strict_encode64(Rails.root.join("test", filename).binread)

      page.execute_script(<<~JS, encoded, filename, content_type)
        const [b64, name, type] = arguments;
        const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
        const transfer = new DataTransfer();
        transfer.items.add(new File([bytes], name, { type }));
        document.querySelector('[data-controller="dropzone"]').dispatchEvent(
          new DragEvent("drop", { dataTransfer: transfer, bubbles: true, cancelable: true })
        );
      JS
    end
end
