class AddExtraQuestionTypes < ActiveRecord::Migration
  def self.up
    add_attachment :admin_answers, :file

    say_with_time("Updating question response_types to new styles") do
      ::Admin::Question.where("response_type": 'String').update_all("response_type": 'Short Text')
      ::Admin::Question.where("response_type": 'Text').update_all("response_type": 'Long Text')
      ::Admin::Question.where("response_type": 'Integer').update_all("response_type": 'Number')
    end
  end

  def self.down
    remove_attachment :admin_answers, :file

    say_with_time("Reverting question response_types to old styles") do
      ::Admin::Question.where("response_type": 'Short Text').update_all("response_type": 'String')
      ::Admin::Question.where("response_type": 'Long Text').update_all("response_type": 'Text')
      ::Admin::Question.where("response_type": 'Number').update_all("response_type": 'Integer')
    end
  end
end
