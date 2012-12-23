class Show < Event
  has_many :reviews

  has_many :feedbacks, :class_name => "Admin::Feedback"
  has_many :questionnaires, :class_name => "Admin::Questionnaires::Questionnaire"
  
  attr_accessible :reviews, :reviews_attributes
  
  accepts_nested_attributes_for :reviews, :reject_if => :all_blank, :allow_destroy => true
  
  def create_questionnaire(name)
    questionnaire = Admin::Questionnaires::Questionnaire.new
    questionnaire.show = self
    questionnaire.name = name
    questionnaire.save!
  end
end