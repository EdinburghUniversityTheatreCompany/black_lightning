# == Schema Information
#
# Table name: attachments
#
# *id*::                <tt>integer, not null, primary key</tt>
# *editable_block_id*:: <tt>integer</tt>
# *name*::              <tt>string(255)</tt>
# *file_file_name*::    <tt>string(255)</tt>
# *file_content_type*:: <tt>string(255)</tt>
# *file_file_size*::    <tt>integer</tt>
# *file_updated_at*::   <tt>datetime</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class AttachmentTest < ActionView::TestCase
  include NameHelper

  test 'slug' do
    attachment = FactoryBot.create(:show_attachment)
    assert_equal attachment.name, attachment.slug
  end

  test 'attachment for answers' do
    attachment = FactoryBot.create(:answer_attachment)

    assert_equal "#{get_object_name(attachment.item.answerable)} for #{get_object_name(attachment.item.answerable.event)}", attachment.item_name
  end

  test 'item name for event' do
    attachment = FactoryBot.create(:show_attachment)
    show = attachment.item

    assert_equal show.name, attachment.item_name
  end

  test 'item name with no answerable' do
    attachment = FactoryBot.create(:answer_attachment)

    attachment.item.answerable = nil
    attachment.item.save(validate: false)

    assert_equal 'No Answerable for Item', attachment.item_name
  end

  test 'item name with no item' do
    attachment = FactoryBot.create(:editable_block_attachment)

    attachment.item = nil
    attachment.save(validate: false)

    assert_equal 'No Item', attachment.item_name
  end

  test 'item name with answerable without event attached' do
    attachment = FactoryBot.create(:answer_attachment)

    attachment.item.answerable.event = nil
    attachment.item.answerable.save(validate: false)

    assert_equal get_object_name(attachment.item.answerable), attachment.item_name
  end
end
