# == Schema Information
#
# Table name: pictures
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *description*::        <tt>text(65535)</tt>
# *gallery_id*::         <tt>integer</tt>
# *gallery_type*::       <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class PictureTest < ActionView::TestCase
  test 'missing image' do
    picture = FactoryBot.create(:picture)
    picture.image.purge
    picture.save(validate: false)

    assert_equal 'active_storage_default-missing.png', picture.fetch_image.filename.to_s
  end

  test 'thumb url' do
    picture = FactoryBot.create(:picture)
    assert_includes picture.thumb_url, 'test.png'
  end

  test 'display url' do
    picture = FactoryBot.create(:picture)
    assert_includes picture.display_url, 'test.png'
  end
end
