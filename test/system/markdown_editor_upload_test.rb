require "application_system_test_case"

# MarkdownController#upload needs a signed-in user, so the editor offers upload only then.
class MarkdownEditorUploadTest < ApplicationSystemTestCase
  # A DataTransfer of the files in the script's first argument, each [name, type, base64 bytes]; a
  # file given no bytes holds "x".
  DATA_TRANSFER_JS = <<~JS.freeze
    arguments[0].reduce((transfer, [name, type, base64]) => {
      const bytes = base64 ? Uint8Array.from(atob(base64), c => c.charCodeAt(0)) : "x"
      transfer.items.add(new File([bytes], name, { type }))
      return transfer
    }, new DataTransfer())
  JS

  test "a logged-out visitor's editor works, offers no image upload and swallows a dropped file" do
    visit new_complaint_path

    assert_selector ".milkdown-editor-wrap .ProseMirror"
    assert_no_selector "button[title='Upload image']"
    assert_no_selector "[data-controller='markdown-editor'] input[type='file']", visible: :all
    assert drop_file_on_editor, "an unhandled drop makes the browser open the file in place of the form"
  end

  test "a signed-in member's editor offers image upload" do
    login_as users(:member)
    visit new_complaint_path

    assert_selector ".milkdown-editor-wrap .ProseMirror"
    assert_selector "button[title='Upload image']"
  end

  test "a member is told why the server refused a dropped image, and nothing is inserted" do
    visit_editor_as_member
    drop_file_on_editor("photo.heic", "image/heic")

    assert_selector ".swal2-popup", text: "photo.heic: Only PNG, JPEG, GIF and WebP images can be uploaded."
    assert_nothing_inserted
  end

  test "a member is told they cannot add images to a record they cannot edit" do
    visit_editor_as_member
    execute_script(<<~JS, news(:current_news).id.to_s)
      const editor = document.querySelector("[data-controller='markdown-editor']")
      editor.dataset.markdownEditorItemTypeValue = "News"
      editor.dataset.markdownEditorItemIdValue = arguments[0]
    JS
    drop_file_on_editor

    assert_selector ".swal2-popup", text: "poster.png: You can't add images to this record."
    assert_nothing_inserted
  end

  test "a member whose sign-in has ended is told to copy their text before signing in again" do
    visit_editor_as_member
    # A password change elsewhere ends this sign-in but leaves the page's CSRF token valid.
    users(:member).update_column(:encrypted_password, Devise::Encryptor.digest(User, "changed-elsewhere"))
    drop_file_on_editor

    assert_selector ".swal2-popup", text: "poster.png: You've been signed out. Copy what you've written " \
                                          "before you sign in again: this page can't save it after that."
    assert_nothing_inserted
  end

  test "a member is told a dropped file is not an image" do
    visit_editor_as_member
    drop_file_on_editor("minutes.pdf", "application/pdf")

    assert_selector ".swal2-popup", text: "minutes.pdf isn't an image."
    assert_nothing_inserted
  end

  test "one alert lists every failure in a drop, and the image that uploaded goes in" do
    visit_editor_as_member
    drop_files_on_editor([
      real_png,
      [ "minutes.pdf", "application/pdf" ],
      [ "photo.heic", "image/heic" ]
    ])

    within(".swal2-popup") do
      assert_text "minutes.pdf isn't an image."
      assert_text "photo.heic: Only PNG, JPEG, GIF and WebP images can be uploaded."
    end
    assert_selector ".ProseMirror img", count: 1
  end

  test "a paste's refused image is reported, but its files that are not images pass silently" do
    visit_editor_as_member
    paste_files_on_editor([ real_png, [ "minutes.pdf", "application/pdf" ], [ "photo.heic", "image/heic" ] ])

    # One alert holds every failure, so the PDF would be named beside the HEIC.
    within(".swal2-popup") do
      assert_text "photo.heic: Only PNG, JPEG, GIF and WebP images can be uploaded."
      assert_no_text "minutes.pdf"
    end
    assert_selector ".ProseMirror img", count: 1
  end

  test "a picked image that cannot reach the server is reported, and the picker is cleared to pick it again" do
    visit_editor_as_member
    point_upload_at_nothing
    file_input = find("[data-controller='markdown-editor'] input[type='file']", visible: :all)
    file_input.set(file_fixture("test_image.png").to_s)

    assert_selector ".swal2-popup", text: "test_image.png couldn't be uploaded. Check your connection and try again."
    assert_equal "", file_input.value
    assert_nothing_inserted
  end

  test "a dropped image that cannot reach the server is reported, and its placeholder goes" do
    visit_editor_as_member
    point_upload_at_nothing
    drop_file_on_editor

    assert_selector ".swal2-popup", text: "poster.png couldn't be uploaded. Check your connection and try again."
    assert_nothing_inserted
  end

  private

  def visit_editor_as_member
    login_as users(:member)
    visit new_complaint_path
    assert_selector ".milkdown-editor-wrap .ProseMirror"
  end

  # The page's CSP refuses another origin, so the fetch fails as it does when the connection drops.
  def point_upload_at_nothing
    execute_script(<<~JS)
      document.querySelector("[data-controller='markdown-editor']").dataset.markdownEditorUploadUrlValue =
        "http://127.0.0.1:9/markdown/upload"
    JS
  end

  def assert_nothing_inserted
    assert_no_selector ".ProseMirror img"
    assert_no_text "Upload in progress"
  end

  def drop_file_on_editor(name = "poster.png", type = "image/png") = drop_files_on_editor([ [ name, type ] ])

  # One the server stores, unlike the other files here.
  def real_png = [ "poster.png", "image/png", Base64.strict_encode64(file_fixture("test_image.png").binread) ]

  # Returns whether the editor cancelled the drop.
  def drop_files_on_editor(files)
    evaluate_script(<<~JS, files)
      (() => {
        const prose = document.querySelector(".milkdown-editor-wrap .ProseMirror")
        const { x, y } = prose.getBoundingClientRect()
        return !prose.dispatchEvent(new DragEvent("drop", {
          dataTransfer: #{DATA_TRANSFER_JS}, clientX: x + 10, clientY: y + 10, bubbles: true, cancelable: true
        }))
      })()
    JS
  end

  def paste_files_on_editor(files)
    execute_script(<<~JS, files)
      document.querySelector(".milkdown-editor-wrap .ProseMirror").dispatchEvent(new ClipboardEvent("paste", {
        clipboardData: #{DATA_TRANSFER_JS}, bubbles: true, cancelable: true
      }))
    JS
  end
end
