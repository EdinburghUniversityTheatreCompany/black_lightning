require 'test_helper'

class Admin::EditableBlockTest < ActiveSupport::TestCase
  test 'get list of groups' do
    groups = %w[smurf pineapple hexagon Hubschrauber]

    groups.each do |group|
      FactoryBot.create :editable_block, group: group
    end

    # Assert the intersection between groups and the result equals groups
    # aka, the result has to contain all groups.
    assert groups & Admin::EditableBlock.groups == groups
  end
end
