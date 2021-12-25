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

FactoryBot.define do
  factory :attachment do
    name { generate(:random_string) }

    access_level { [0, 1, 2].sample }

    file { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.pdf'), 'application/pdf') }

    transient do
      tag_count { 1 }
    end

    after(:create) do |attachment, evaluator|
      attachment.attachment_tags << AttachmentTag.all.sample(evaluator.tag_count)
    end
  end

  factory :editable_block_attachment, parent: :attachment do
    association :item, factory: :editable_block
  end

  factory :show_attachment, parent: :attachment do
    association :item, factory: :show
  end

  factory :answer_attachment, parent: :attachment do
    association :item, factory: :answer
  end
end
