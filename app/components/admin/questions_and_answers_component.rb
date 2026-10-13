class Admin::QuestionsAndAnswersComponent < ViewComponent::Base
  def initialize(answers:, flush: false)
    @answers = answers.includes(:question)
    @flush = flush
  end

  private

  def separator_class = @flush ? "border-t border-gray-200" : "border-t border-gray-200 pt-4 mt-4"
  def question_class = @flush ? "px-4 py-3 text-sm text-gray-900" : "mb-1 mt-0.5 text-sm text-gray-900"
  def answer_class = @flush ? "bg-gray-50 px-4 py-3 border-t border-gray-200 text-sm text-gray-700" : "mt-3 bg-gray-50 rounded px-3 pb-3 pt-3.5 text-sm text-gray-700"
end
