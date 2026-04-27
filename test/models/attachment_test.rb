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
require "test_helper"

class AttachmentTest < ActionView::TestCase
  include NameHelper

  test "slug" do
    attachment = FactoryBot.create(:show_attachment)
    assert_equal attachment.name, attachment.slug
  end

  test "attachment for answers" do
    attachment = FactoryBot.create(:answer_attachment)

    assert_equal "#{get_object_name(attachment.item.answerable)} for #{get_object_name(attachment.item.answerable.event)}", attachment.item_name
  end

  test "item name for event" do
    attachment = FactoryBot.create(:show_attachment)
    show = attachment.item

    assert_equal show.name, attachment.item_name
  end

  test "item name with no answerable" do
    attachment = FactoryBot.create(:answer_attachment)

    attachment.item.answerable = nil
    attachment.item.save(validate: false)

    assert_equal "No Answerable for Item", attachment.item_name
  end

  test "item name with no item" do
    attachment = FactoryBot.create(:editable_block_attachment)

    attachment.item = nil
    attachment.save(validate: false)

    assert_equal "No Item", attachment.item_name
  end

  test "item name with answerable without event attached" do
    attachment = FactoryBot.create(:answer_attachment)

    attachment.item.answerable.event = nil
    attachment.item.answerable.save(validate: false)

    assert_equal get_object_name(attachment.item.answerable), attachment.item_name
  end

  test "rejects svg files" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.build(:attachment, item: editable_block)
    attachment.file.attach(io: File.open(Rails.root.join("test", "test.svg")), filename: "evil.svg", content_type: "image/svg+xml")

    assert_not attachment.valid?
    assert_not attachment.errors[:file].empty?
  end

  test "rejects html files" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.build(:attachment, item: editable_block)
    attachment.file.attach(io: StringIO.new("<html><script>alert(1)</script></html>"), filename: "evil.html", content_type: "text/html")

    assert_not attachment.valid?
    assert_not attachment.errors[:file].empty?
  end

  test "allows pdf files" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.create(:attachment, item: editable_block, file: Rack::Test::UploadedFile.new(Rails.root.join("test", "test.pdf"), "application/pdf"))
    assert attachment.valid?
    assert_equal "application/pdf", attachment.file.content_type
  end

  test "allows image files" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.build(:attachment, item: editable_block)
    attachment.file.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "image.png", content_type: "image/png")
    assert attachment.valid?
  end

  test "allows text files" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.build(:attachment, item: editable_block)
    attachment.file.attach(io: StringIO.new("hello world"), filename: "document.txt", content_type: "text/plain")
    assert attachment.valid?
  end

  test "allows office documents" do
    editable_block = admin_editable_blocks(:public)
    attachment = FactoryBot.build(:attachment, item: editable_block)
    attachment.file.attach(io: StringIO.new("fake docx"), filename: "document.docx", content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    assert attachment.valid?
  end
end
