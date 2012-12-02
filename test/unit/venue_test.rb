# == Schema Information
#
# Table name: venues
#
#  id                 :integer          not null, primary key
#  name               :string(255)
#  tagline            :string(255)
#  description        :text
#  location           :string(255)
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

require 'test_helper'

class VenueTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
