##
# Represents the different role that a User may have. Permissions are asigned using the
# Admin::PermissionsController
#
# == Schema Information
#
# Table name: roles
#
# *id*::            <tt>integer, not null, primary key</tt>
# *name*::          <tt>string(255)</tt>
# *resource_id*::   <tt>integer</tt>
# *resource_type*:: <tt>string(255)</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
##
class Role < ActiveRecord::Base
  has_and_belongs_to_many :users, :join_table => :users_roles
  has_and_belongs_to_many :permissions, :class_name => "Admin::Permission"

  belongs_to :resource, :polymorphic => true

  attr_accessible :name

  scopify
end
