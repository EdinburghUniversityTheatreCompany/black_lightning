# == Schema Information
#
# Table name: pictures
#
#  id                 :integer          not null, primary key
#  description        :text
#  gallery_id         :integer
#  gallery_type       :string(255)
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

require 'test_helper'

class PictureTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
