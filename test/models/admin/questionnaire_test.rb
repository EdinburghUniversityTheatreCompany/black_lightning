require 'test_helper'

class Admin::QuestionnaireTest < ActiveSupport::TestCase
  test 'instantiate answers' do
    questionnaire = FactoryBot.create(:questionnaire)

    # Remove answers from every question so they are all unanswered.
    questionnaire.questions.each { |question| question.answers.delete_all }

    assert_not_equal 0, questionnaire.questions.count, 'All questionnaire questions are already answered, so this test does not test anything. Change this test so not all questions are answered.'

    # Need to create as many answers as there are questions, as they are all unanswered.
    assert_difference 'questionnaire.answers.count', questionnaire.questions.count do
      questionnaire.instantiate_answers!
    end
  end
end
