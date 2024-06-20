# == Schema Information
#
# Table name: emails
#
# *id*::                   <tt>bigint, not null, primary key</tt>
# *email*::                <tt>string(255)</tt>
# *attached_object_type*:: <tt>string(255), not null</tt>
# *attached_object_id*::   <tt>bigint, not null</tt>
# *created_at*::           <tt>datetime, not null</tt>
# *updated_at*::           <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class EmailTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
