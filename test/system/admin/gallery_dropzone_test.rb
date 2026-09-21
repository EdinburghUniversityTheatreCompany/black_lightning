require "application_system_test_case"

# The admin event form's gallery uploader is the only place the dropzone library
# is used, and the drag-and-drop is the library's own — so no request test can
# reach it, and a major upgrade (5 → 6 removed Dropzone.autoDiscover, .extend
# and .version) could break every admin picture upload with nothing red to show.
class Admin::GalleryDropzoneTest < ApplicationSystemTestCase
  # DirectUploadController copies the file input's name onto the hidden field it
  # fills with the signed id, so this is what proves the upload reached the FORM
  # rather than just the screen.
  FIELD_NAME = "dropzone_pictures[files][]".freeze

  setup do
    login_as users(:admin)
  end

  test "a file dropped on the gallery uploader is direct-uploaded and attached to the form" do
    show = FactoryBot.create(:show)
    visit edit_admin_show_url(show)

    assert_selector ".dropzone[data-controller='dropzone']"

    # The blob row comes from POST /rails/active_storage/direct_uploads, so
    # counting it separates "a preview was drawn" from "the file reached us".
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      drop_file("test.png", "image/png")
      assert_selector ".dz-preview.dz-success", wait: 15
    end

    # Two hidden fields carry this name: the empty one Rails emits so a
    # `multiple` file input still posts, and the one DirectUploadController adds.
    signed_ids = all("input[type='hidden'][name='#{FIELD_NAME}']", visible: :all)
                 .map(&:value).reject(&:blank?)

    assert_equal [ ActiveStorage::Blob.order(:id).last.signed_id ], signed_ids,
                 "the direct upload's signed id never reached the form"
  end

  test "the drop target is live rather than relying on the library's own discovery" do
    show = FactoryBot.create(:show)
    visit edit_admin_show_url(show)

    # Dropzone sets `element.dropzone` to itself on attach. The
    # dropzone/dz-clickable/dz-message classes are in the partial's own markup
    # and are there whether or not anything attached, so they prove nothing.
    assert page.evaluate_script(
      "!!document.querySelector('[data-controller=\"dropzone\"]').dropzone"
    ), "the dropzone widget was never constructed on the drop target"

    assert_no_selector "input[type='file'][name='#{FIELD_NAME}']", visible: true
  end

  private

    # attach_file would drive the native input the controller has disabled;
    # Dropzone only listens for a drop carrying a DataTransfer.
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
