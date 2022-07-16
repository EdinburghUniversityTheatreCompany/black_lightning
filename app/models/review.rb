##
# Represents a review for a Show.
#
# == Schema Information
#
# Table name: reviews
#
# *id*::           <tt>integer, not null, primary key</tt>
# *show_id*::      <tt>integer</tt>
# *reviewer*::     <tt>string(255)</tt>
# *body*::         <tt>text(65535)</tt>
# *rating*::       <tt>decimal(2, 1)</tt>
# *review_date*::  <tt>date</tt>
# *created_at*::   <tt>datetime, not null</tt>
# *updated_at*::   <tt>datetime, not null</tt>
# *organisation*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
class Review < ApplicationRecord
  validates :body, :reviewer, :review_date, :rating, presence: true
  validates :rating, numericality: { greater_than: 0 }

  belongs_to :show

  # TOOD: Include link to the original review
end
