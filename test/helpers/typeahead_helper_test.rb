require 'test_helper'

class TypeaheadHelperTest < ActionView::TestCase
  include ApplicationHelper
  
  test 'positions array' do
    assert position_typeahead.is_a?(Array)
  end

  test 'sanitize user typeahead attributes' do
    staffing_jobs_attributes = {
      '0' => { id: '52', name: 'High Priest',    user_name_field: 'Finbar', user_id: '2', _destroy: 'false' },
      '1' => { id: '53', name: 'Lackey',         user_name_field: 'Dennis', user_id: '',  _destroy: 'false' },
      '2' => { id: '54', name: 'Dinner',         user_name_field: 'Evil',   user_id: '',  _destroy: 'false' },
      '3' => { id: '55', name: 'Dungeon Master', user_name_field: '',       user_id: '',  _destroy: 'false' }
    }

    # We expect the sanitizer to drop the lines that have a value in the user name field, but no associated user id.
    # We also expect the sanitizer to remove the user_name_field from the result, as it is not an actual field on the association.
    expected_result = {
      '0' => { id: '52', name: 'High Priest',    user_id: '2', _destroy: 'false' },
      '3' => { id: '55', name: 'Dungeon Master', user_id: '',  _destroy: 'false' }
    }

    other_staffing_jobs_attributes = staffing_jobs_attributes.dup
    assert_equal ['Dennis', 'Evil'], sanitize_user_typeahead_attributes!(staffing_jobs_attributes, false)
    assert_nil flash[:error]
    assert_equal expected_result, staffing_jobs_attributes

    assert_equal ['Dennis', 'Evil'], sanitize_user_typeahead_attributes!(other_staffing_jobs_attributes, true)
    assert_equal ['There was a typo entering the name of the users Dennis and Evil. Their previous name has been restored.'], flash[:error]
    assert_equal expected_result, other_staffing_jobs_attributes
  end

  test 'sanitize user typeahead attributes only removes user name field on proper hash' do
    staffing_jobs_attributes = {
      '0' => { id: '52', name: 'High Priest',    user_name_field: 'Finbar', user_id: '2', _destroy: 'false' },
      '1' => { id: '53', name: 'Lackey',         user_name_field: 'Dennis', user_id: '5', _destroy: 'false' },
      '2' => { id: '54', name: 'Dinner',         user_name_field: '',       user_id: '',  _destroy: 'true'  },
      '3' => { id: '55', name: 'Dungeon Master', user_name_field: '',       user_id: '',  _destroy: 'false' }
    }

    expected_result = {
      '0' => { id: '52', name: 'High Priest',    user_id: '2', _destroy: 'false' },
      '1' => { id: '53', name: 'Lackey',         user_id: '5', _destroy: 'false' },
      '2' => { id: '54', name: 'Dinner',         user_id: '',  _destroy: 'true'  },
      '3' => { id: '55', name: 'Dungeon Master', user_id: '',  _destroy: 'false' }
    }

    assert_equal [], sanitize_user_typeahead_attributes!(staffing_jobs_attributes, true)
    assert_equal expected_result, staffing_jobs_attributes
    assert_nil flash[:error]
  end

  test 'sanitize user typeahead attributes does nothing on hash without name field' do
    staffing_jobs_attributes = {
      '0' => { id: '52', name: 'High Priest',    user_id: '2', _destroy: 'false' },
      '1' => { id: '53', name: 'Lackey',         user_id: '',  _destroy: 'true'  },
      '2' => { id: '54', name: 'Dinner',         user_id: '7', _destroy: 'false' },
      '3' => { id: '55', name: 'Dungeon Master', user_id: '',  _destroy: 'false' }
    }

    expected_result = staffing_jobs_attributes.dup

    assert_equal [], sanitize_user_typeahead_attributes!(staffing_jobs_attributes, true)
    assert_equal expected_result, staffing_jobs_attributes
    assert_nil flash[:error]
  end

  test 'sanitize user typeahead attributes does nothing on nil or empty' do
    assert_equal [], sanitize_user_typeahead_attributes!(nil, true)
    assert_nil flash[:error]
    assert_equal [], sanitize_user_typeahead_attributes!({}, true)
    assert_nil flash[:error]
  end
end
