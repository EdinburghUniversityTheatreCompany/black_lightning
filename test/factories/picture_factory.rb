##
# Represents a picture in the polymorphic association <tt>gallery</tt>
#
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

FactoryBot.define do
  factory :picture, class: Picture do
    association :gallery, factory: :show
    description { generate(:random_text) }

    transient do
      attach_image { true }
    end

    image { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.png'), 'image/png') if attach_image }
  end
end
