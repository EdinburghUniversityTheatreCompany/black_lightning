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
#
# *id*::         <tt>integer, not null, primary key</tt>
# *email*::      <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
##
class NewsletterSubscriber < ApplicationRecord
  validates :email, presence: true
end
