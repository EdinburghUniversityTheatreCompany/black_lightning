class AddExtraQuestionTypes < ActiveRecord::Migration
  def self.up
    add_attachment :admin_answers, :file

    say_with_time("Updating question response_types to new styles") do
      ::Admin::Question.update_all("admin_questions.response_type = 'Short Text'", "admin_questions.response_type = 'String'")
      ::Admin::Question.update_all("admin_questions.response_type = 'Long Text'", "admin_questions.response_type = 'Text'")
      ::Admin::Question.update_all("admin_questions.response_type = 'Number'", "admin_questions.response_type = 'Integer'")
    end
  end

  def self.down
    remove_attachment :admin_answers, :file

    say_with_time("Reverting question response_types to old styles") do
      ::Admin::Question.update_all("admin_questions.response_type = 'String'", "admin_questions.response_type = 'Short Text'")
      ::Admin::Question.update_all("admin_questions.response_type = 'Text'", "admin_questions.response_type = 'Long Text'")
      ::Admin::Question.update_all("admin_questions.response_type = 'Integer'", "admin_questions.response_type = 'Number'")
    end
  end
end
