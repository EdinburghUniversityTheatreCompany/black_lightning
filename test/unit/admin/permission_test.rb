# == Schema Information
#
# Table name: admin_permissions
#
# *id*::            <tt>integer, not null, primary key</tt>
# *name*::          <tt>string(255)</tt>
# *description*::   <tt>string(255)</tt>
# *action*::        <tt>string(255)</tt>
# *subject_class*:: <tt>string(255)</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

require 'test_helper'

class Admin::PermissionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
