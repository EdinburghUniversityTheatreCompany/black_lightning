require 'test_helper'

class Admin::QuestionnaireTest < ActiveSupport::TestCase
  test 'instantiate answers' do
    questionnaire = FactoryBot.create(:questionnaire)

    unanswered_questions = questionnaire.questions.to_a.count { |question| question.answers.where(answerable: questionnaire).empty? }

    assert_not_equal 0, unanswered_questions, 'All questionnaire questions are already answered, so this test does not test anything. Change this test so not all questions are answered.'

    assert_difference 'questionnaire.answers.count', unanswered_questions do
      questionnaire.instantiate_answers!
    end
  end
end
