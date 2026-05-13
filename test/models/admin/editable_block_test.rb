# == Schema Information
#
# Table name: admin_editable_blocks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *content*::    <tt>text(65535)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *admin_page*:: <tt>boolean</tt>
# *group*::      <tt>string(255)</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::EditableBlockTest < ActiveSupport::TestCase
  test "get list of groups" do
    groups = %w[smurf pineapple hexagon Hubschrauber]

    groups.each do |group|
      FactoryBot.create :editable_block, group: group
    end

    # Assert the intersection between groups and the result equals groups
    # aka, the result has to contain all groups.
    assert groups & Admin::EditableBlock.groups == groups
  end

  test "for_subpage returns blocks whose url starts with the given prefix" do
    about_block   = FactoryBot.create(:editable_block, url: "about/team")
    contact_block = FactoryBot.create(:editable_block, url: "contact/info")
    root_block    = FactoryBot.create(:editable_block, url: nil)

    results = Admin::EditableBlock.for_subpage("about")
    assert_includes results, about_block
    assert_not_includes results, contact_block
    assert_not_includes results, root_block
  end

  test "url is downcased after saving" do
    block = FactoryBot.create(:editable_block, url: "About/Team")

    assert_equal "about/team", block.url
  end
end
