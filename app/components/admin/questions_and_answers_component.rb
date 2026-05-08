class Admin::QuestionsAndAnswersComponent < ViewComponent::Base
  def initialize(answers:, flush: false)
    @answers = answers.includes(:question)
    @flush = flush
  end
end
