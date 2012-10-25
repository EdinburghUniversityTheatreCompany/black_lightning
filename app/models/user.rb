class User < ActiveRecord::Base
  rolify
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :trackable

  #set our own validations
  validates :password, :presence => true, :if => lambda { new_record? || !password.nil? || !password.blank? }
  validates :email, :presence => true


  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me, :first_name, :last_name, :role_ids, :phone_number
  # attr_accessible :title, :body

  def name
  	"#{self.first_name} #{self.last_name}"
  end
end
