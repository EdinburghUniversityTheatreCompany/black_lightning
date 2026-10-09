require "application_system_test_case"

# MarkdownController#upload needs a signed-in user, so the editor offers upload only then.
class MarkdownEditorUploadTest < ApplicationSystemTestCase
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

  private

  # Returns whether the editor cancelled the drop.
  def drop_file_on_editor
    evaluate_script(<<~JS)
      (() => {
        const prose = document.querySelector(".milkdown-editor-wrap .ProseMirror")
        const { x, y } = prose.getBoundingClientRect()
        const dataTransfer = new DataTransfer()
        dataTransfer.items.add(new File(["x"], "poster.png", { type: "image/png" }))
        return !prose.dispatchEvent(new DragEvent("drop", {
          dataTransfer, clientX: x + 10, clientY: y + 10, bubbles: true, cancelable: true
        }))
      })()
    JS
  end
end
