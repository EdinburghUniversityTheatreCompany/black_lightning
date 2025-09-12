# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text(65535)</tt>
# *slug*::               <tt>string(255)</tt>
# *publish_date*::       <tt>datetime</tt>
# *show_public*::        <tt>boolean</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *author_id*::          <tt>integer</tt>
#--
# == Schema Information End
#++

# Read about fixtures at http://api.rubyonrails.org/classes/ActiveRecord/Fixtures.html

FactoryBot.define do
  factory :news do
    title { generate(:random_string) }
    slug  { title.gsub(/\s+/, "-").gsub(/[^a-zA-Z0-9\-]/, "").downcase.gsub(/\-{2,}/, "-") }

    body  { generate(:random_text) }

    publish_date { generate(:random_date) }
    show_public  { [ true, false ].sample }

    association :author, factory: :user
  end
end
