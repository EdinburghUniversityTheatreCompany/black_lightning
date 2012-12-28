# == Schema Information
#
# Table name: seasons
#
# *id*::          <tt>integer, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text</tt>
# *start_date*::  <tt>date</tt>
# *end_date*::    <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
# *slug*::        <tt>string(255)</tt>
#--
# == Schema Information End
#++

class Season < ActiveRecord::Base
  def to_param
    slug
  end
  attr_accessible :description, :end_date, :name, :start_date, :slug
  
  validates :slug, :presence => true, :uniqueness => true
  
  has_many :shows
  
  
end
