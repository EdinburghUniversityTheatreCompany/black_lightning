# == Schema Information
#
# Table name: video_links
#
# *id*::           <tt>bigint, not null, primary key</tt>
# *name*::         <tt>string(255), not null</tt>
# *link*::         <tt>string(255), not null</tt>
# *access_level*:: <tt>integer, default(1), not null</tt>
# *order*::        <tt>integer</tt>
# *item_type*::    <tt>string(255)</tt>
# *item_id*::      <tt>bigint</tt>
# *created_at*::   <tt>datetime, not null</tt>
# *updated_at*::   <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class VideoLinkTest < ActionView::TestCase
  test 'submitting invalid link' do
    assert_raises ActiveRecord::RecordInvalid do
      FactoryBot.create(:video_link, link: 'WAH')
    end
  end

  test 'embedding for invalid link' do
    video_link = FactoryBot.create(:video_link)
    video_link.update_attribute(:link, 'WAH')

    assert_equal 'The video link is not valid.', video_link.embed_code
  end

  test 'embedding for valid link' do
    video_link = FactoryBot.create(:video_link)

    assert_not_equal 'The video link is not valid.', video_link.embed_code
    assert_includes video_link.embed_code, 'youtube-nocookie.com'
  end

  test 'embedding Facebook link' do
    video_link = FactoryBot.create(:video_link, link: 'https://fb.watch/4Eo-S1p6H9/')

    assert_not_equal 'The video link is not valid.', video_link.embed_code
    assert_includes video_link.embed_code, 'facebook.com'
  end
end
