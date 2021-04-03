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
class VideoLink < ApplicationRecord
  belongs_to :item, polymorphic: true

  validates :name, :link, :access_level, presence: true

  # They're the same, so why not?
  ACCESS_LEVELS = Attachment.ACCESS_LEVELS
end
