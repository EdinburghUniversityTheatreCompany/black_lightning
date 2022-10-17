require 'test_helper'

class TypeaheadHelperTest < ActionView::TestCase
  include ApplicationHelper
  
  test 'positions array' do
    assert position_typeahead.is_a?(Array)
  end
end
