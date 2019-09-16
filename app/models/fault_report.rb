class FaultReport < ActiveRecord::Base
  belongs_to :reported_by,  class_name: User
  belongs_to :fixed_by,     class_name: User
  enum severity: [:annoying, :probably_worth_fixing, :show_impeding, :dangerous]
  enum status: [:reported, :in_progress, :cant_fix, :wont_fix, :on_hold, :completed]
end
