# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *publicity_text*::         <tt>text(65535)</tt>
# *members_onlu_text*::      <tt>text(65535)</tt>
# *xts_id*::                 <tt>integer</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *is_public*::              <tt>boolean</tt>
# *image_file_name*::        <tt>string(255)</tt>
# *image_content_type*::     <tt>string(255)</tt>
# *image_file_size*::        <tt>integer</tt>
# *image_updated_at*::       <tt>datetime</tt>
# *start_date*::             <tt>date</tt>
# *end_date*::               <tt>date</tt>
# *venue_id*::               <tt>integer</tt>
# *season_id*::              <tt>integer</tt>
# *author*::                 <tt>string(255)</tt>
# *type*::                   <tt>string(255)</tt>
# *price*::                  <tt>string(255)</tt>
# *spark_seat_slug*::        <tt>string(255)</tt>
# *maintenance_debt_start*:: <tt>date</tt>
# *staffing_debt_start*::    <tt>date</tt>
# *proposal_id*::            <tt>integer</tt>
#--
# == Schema Information End
#++

class Workshop < Event
  # Validate uniqueness on Event Subtype basis instead of on the event.
  # Otherwise, you cannot have two different types with the same slug.
  validates :slug, uniqueness: { case_sensitive: false }
end
