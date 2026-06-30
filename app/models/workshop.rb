
# == Schema Information
#
# Table name: events
# Database name: primary
#
#  id                      :integer          not null, primary key
#  author                  :string(255)
#  content_warnings        :text(16777215)
#  end_date                :date
#  image_content_type      :string(255)
#  image_file_name         :string(255)
#  image_file_size         :integer
#  image_updated_at        :datetime
#  is_public               :boolean
#  maintenance_debt_amount :integer
#  maintenance_debt_start  :date
#  members_only_text       :text(16777215)
#  name                    :string(255)
#  pretix_shown            :boolean
#  pretix_slug_override    :string(255)
#  pretix_view             :string(255)
#  price                   :string(255)
#  publicity_text          :text(16777215)
#  slug                    :string(255)
#  spark_seat_slug         :string(255)
#  staffing_debt_amount    :integer
#  staffing_debt_start     :date
#  start_date              :date
#  tagline                 :string(255)
#  type                    :string(255)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  company_id              :bigint
#  proposal_id             :integer
#  season_id               :integer
#  venue_id                :integer
#  xts_id                  :integer
#
# Indexes
#
#  index_events_on_author                  (author)
#  index_events_on_company_id              (company_id)
#  index_events_on_date_range              (start_date,end_date)
#  index_events_on_end_date_and_is_public  (end_date,is_public)
#  index_events_on_proposal_id             (proposal_id)
#  index_events_on_season_id               (season_id)
#  index_events_on_venue_id                (venue_id)
#
# Foreign Keys
#
#  fk_rails_...  (company_id => companies.id)
#  fk_rails_...  (proposal_id => admin_proposals_proposals.id)
#
class Workshop < Event
  # Validate uniqueness on Event Subtype basis instead of on the event.
  # Otherwise, you cannot have two different types with the same slug.
  validates :slug, uniqueness: { case_sensitive: false }

  def self.ransackable_associations(auth_object = nil)
    super
  end
end
