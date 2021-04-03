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

def random_youtube_link
  id = Faker::Alphanumeric.alphanumeric(number: 11)

  templates = [
    "youtu.be/#{id}",
    "https://youtu.be/#{id}",
    "https://www.youtube.com/watch?v=#{id}&list=PLn6KyJ4PmZsPhigNqPlWGEoCgBHJbhib3",
    "www.youtube.com/watch?v=#{id}"
  ]

  return templates.sample
end

FactoryBot.define do
  factory :video_link do
    name { generate(:random_string) }
    link { random_youtube_link }
    access_level { [0, 1, 2].sample }
    order { rand(10) }

    association :item, factory: :show
  end
end
