# == Schema Information
#
# Table name: complaints
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *subject*::     <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *resolved*::    <tt>boolean</tt>
# *comments*::    <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class ComplaintTest < ActiveSupport::TestCase
  test "html class" do
    complaint = FactoryBot.build(:complaint, resolved: true)

    assert_nil complaint.html_class

    complaint.resolved = false

    assert_equal "error", complaint.html_class
 end

  test "cannot destroy complaint" do
    complaint = FactoryBot.build(:complaint)

    assert_no_difference "Complaint.count" do
      assert_not complaint.destroy
    end
  end
end
