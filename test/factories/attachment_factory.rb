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

    association :editable_block, factory: :editable_block

    file { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.pdf'), 'application/pdf') }
  end
end
