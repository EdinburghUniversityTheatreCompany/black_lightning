require "test_helper"

class MdEditorComponentTest < ViewComponent::TestCase
  def render_editor(**args)
    render_inline(TestFormWrapper.new(record: User.new, **args))
  end

  # Renders the component inside a real simple_form builder, which is the only
  # way to get an `f` to hand it.
  class TestFormWrapper < ViewComponent::Base
    def initialize(record:, **editor_args)
      @record = record
      @editor_args = editor_args
    end

    def call
      helpers.simple_form_for(@record, url: "#") do |f|
        render MdEditorComponent.new(f: f, field: :bio, **@editor_args)
      end
    end
  end

  test "rejects an unknown layout rather than rendering something arbitrary" do
    assert_raises(ArgumentError) do
      MdEditorComponent.new(f: nil, field: :bio, layout: :sideways)
    end
  end

  test "the admin layout puts the label in its own column" do
    render_editor

    assert_selector "div.flex.flex-wrap.items-start > div.md\\:w-3\\/12 label"
    assert_selector "div.md\\:w-9\\/12 [data-controller='markdown-editor']"
  end

  # Stacked, with the label carrying the same rules its siblings pick up from
  # col-form-label, so the editor does not read as a different kind of field.
  test "the vertical layout stacks and styles the label like a sibling field" do
    render_editor(layout: :vertical)

    assert_no_selector "div.md\\:w-3\\/12"
    assert_no_selector "div.md\\:w-9\\/12"
    assert_selector "div.mb-4 > label.block.text-sm.font-medium.text-gray-700"
  end

  test "both layouts wire up the markdown editor controller" do
    render_editor(layout: :vertical)

    assert_selector "[data-controller='markdown-editor'] textarea.form-control"
  end
end
