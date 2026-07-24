require "test_helper"

class Admin::QuestionsAndAnswersComponentTest < ViewComponent::TestCase
  # Builds a persisted File answer carrying +count+ attachments and returns it
  # wrapped in a relation (the component calls #includes on its argument).
  def answers_with_attachments(count)
    answer = FactoryBot.create(:answer, response_type: "File")
    count.times { FactoryBot.create(:attachment, item: answer, tag_count: 0) }
    Admin::Answer.where(id: answer.id)
  end

  # A single attachment renders through shared/show_attachment (which exists) and
  # NOT through the multi-attachment gallery.
  test "renders a single attachment without the gallery wrapper" do
    render_inline(Admin::QuestionsAndAnswersComponent.new(answers: answers_with_attachments(1)))

    assert_no_selector "[data-controller='fancybox']"
    assert_no_text "Attachments"
  end

  # Two attachments hit the multi-attachment gallery branch. This is the
  # production 500 (error 132814643): the component rendered 'shared/attachments_gallery'
  # but the partial lives at admin/shared/_attachments_gallery.html.erb, so the
  # lookup raised MissingTemplate whenever an answer had more than one attachment.
  test "renders multiple attachments through the attachments gallery" do
    render_inline(Admin::QuestionsAndAnswersComponent.new(answers: answers_with_attachments(2)))

    assert_selector "[data-controller='fancybox']"
    assert_text "Attachments"
  end

  # Same bug lived in the flush branch used by questionnaires#show.
  test "renders multiple attachments through the gallery in flush mode" do
    render_inline(Admin::QuestionsAndAnswersComponent.new(answers: answers_with_attachments(2), flush: true))

    assert_selector "[data-controller='fancybox']"
    assert_text "Attachments"
  end
end
