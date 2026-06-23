##
# A very basic model that handles entries in the Newsletter signup box on the homepage.
#
#--
# TODO: This should be updated when newsletters are handled by the website.
#++
#
# == Schema Information
#
# Table name: newsletter_subscribers
# Database name: primary
#
#  id         :integer          not null, primary key
#  email      :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_newsletter_subscribers_on_email  (email) UNIQUE
#
class NewsletterSubscriber < ApplicationRecord
  validates :email, presence: true

  normalizes :email, with: ->(email) { email&.downcase&.strip }
end
