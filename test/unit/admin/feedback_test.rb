# == Schema Information
#
# Table name: admin_feedbacks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *show_id*::    <tt>integer</tt>
# *body*::       <tt>text</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

require 'test_helper'

class Admin::FeedbackTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
