class Admin::QuestionsAndAnswersComponent < ViewComponent::Base
  def initialize(answers:)
    @answers = answers.includes(:question)
  end
end
