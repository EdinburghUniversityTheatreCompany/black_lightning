class User < ActiveRecord::Base
  attr_accessor :roles_mask
  include RoleModel
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :recoverable, :rememberable, :trackable, :validatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me, :roles
  # attr_accessible :title, :body
  
  roles_attribute :roles_mask
  
  roles :admin, :committee, :producer, :member # DO NOT change the order of these, or remove roles. Bad things will occur.

end
