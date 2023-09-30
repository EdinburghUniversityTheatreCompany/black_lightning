##
# Represents a review for a Show.
#
# == Schema Information
#
# Table name: reviews
#
# *id*::           <tt>integer, not null, primary key</tt>
# *event_id*::     <tt>integer</tt>
# *reviewer*::     <tt>string(255)</tt>
# *body*::         <tt>text(65535)</tt>
# *rating*::       <tt>decimal(2, 1)</tt>
# *review_date*::  <tt>date</tt>
# *created_at*::   <tt>datetime, not null</tt>
# *updated_at*::   <tt>datetime, not null</tt>
# *title*::        <tt>string(255)</tt>
# *url*::          <tt>string(255)</tt>
# *organisation*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
class Review < ApplicationRecord
  validates :body, :reviewer, :review_date, :title, presence: true
  validates :rating, numericality: { greater_than: 0, allow_blank: true }

  belongs_to :event

  def reviewer_with_organisation
    return "#{reviewer}#{" for #{organisation}" if organisation.present?}"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[body event_id organisation rating review_date reviewer title url]
  end
end
