# == Schema Information
#
# Table name: venues
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *description*::        <tt>text(65535)</tt>
# *location*::           <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *address*::            <tt>text(65535)</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class VenueTest < ActiveSupport::TestCase
  test 'Get nil for latlng when location is not present' do
    assert_nil venues(:roxy).latlng
  end

  test 'get nil for latlng when location does not contain a comma' do
    venue = venues(:roxy)
    venue.location = "This is a present but invalid location"

    assert_nil venue.latlng
  end

  test 'get nil for latlng when location has more than two comma\'s' do
    venue = venues(:roxy)
    venue.location = '1, 0, 1'

    assert_nil venue.latlng
  end

  test 'get latlng when location is set properly' do
    assert_equal ["55.946324", " -3.190721"], venues(:one).latlng
  end

  test 'do not get popup when location is invalid' do
    assert_nil venues(:roxy).marker_info
  end

  test 'get popup when location is set properly' do
    expected = { latlng: ["55.946324", " -3.190721"], popup: "<b>Bedlam Theatre</b><br><br>11b Bristo Place, EH1 1EZ", open_popup: false}
    assert_equal expected, venues(:one).marker_info
  end

  test 'get popup_description' do
    assert_not_nil venues(:one).popup_description
  end
end
