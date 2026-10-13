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

  # Filename plus the content type a browser declares on upload (zip/xml/octet-stream for container
  # formats). Rows Marcel sniffs by content (images, PDF, SVG) carry real bytes in the third column.
  ALLOWED_UPLOADS = [
    [ "test.pdf",        "application/pdf", -> { File.open(Rails.root.join("test", "test.pdf")) } ],
    [ "image.png",       "image/png", -> { File.open(Rails.root.join("test", "test.png")) } ],
    [ "document.txt",    "text/plain" ],
    [ "document.docx",   "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
    [ "score.mscz",      "application/zip" ],
    [ "score.mscx",      "application/xml" ],
    [ "score.musicxml",  "application/xml" ],
    [ "score.mxl",       "application/zip" ],
    [ "score.mid",       "audio/midi" ],
    [ "score.midi",      "audio/midi" ],
    [ "score.sib",       "application/octet-stream" ],
    [ "score.ly",        "text/plain" ],
    [ "score.abc",       "text/plain" ]
  ].freeze

  REJECTED_UPLOADS = [
    [ "evil.svg",    "image/svg+xml", -> { File.open(Rails.root.join("test", "test.svg")) } ],
    [ "evil.html",   "text/html", -> { StringIO.new("<html><script>alert(1)</script></html>") } ],
    [ "archive.zip", "application/zip" ],
    [ "data.xml",    "application/xml" ]
  ].freeze

  ALLOWED_UPLOADS.each do |filename, content_type, io|
    test "allows #{filename} uploaded as #{content_type}" do
      attachment = upload(filename, content_type, io)

      assert attachment.valid?, "expected #{filename} (#{content_type}) to be allowed, got: #{attachment.errors[:file].to_sentence}"
    end
  end

  REJECTED_UPLOADS.each do |filename, content_type, io|
    test "rejects #{filename} uploaded as #{content_type}" do
      attachment = upload(filename, content_type, io)

      assert_not attachment.valid?
      assert attachment.errors[:file].any?
    end
  end

  # Catches an upgrade re-enabling active_storage_validations' derived `accept`, which greys
  # out valid files in the picker (see its initializer).
  test "a file field carries no accept attribute" do
    builder = ActionView::Helpers::FormBuilder.new(
      :attachment, Attachment.new, ApplicationController.new.view_context, {}
    )

    assert_no_match(/accept=/, builder.file_field(:file))
  end

  private

  def upload(filename, content_type, io)
    FactoryBot.build(:attachment, item: admin_editable_blocks(:public)).tap do |attachment|
      attachment.file.attach(io: io ? io.call : StringIO.new("content"), filename:, content_type:)
    end
  end
end
