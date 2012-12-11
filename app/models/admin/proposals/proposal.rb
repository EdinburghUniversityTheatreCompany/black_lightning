##
# Represents a proposal.
#
# NOTE
#
# If a proposal has the approved attribute set to false, it has been REJECTED.
#
# A proposal still waiting for approval should have approved set to NULL
#
# (Yes, we are using a boolean for something that has three possible values).
#
# == Schema Information
#
# Table name: admin_proposals_proposals
#
# *id*::             <tt>integer, not null, primary key</tt>
# *call_id*::        <tt>integer</tt>
# *show_title*::     <tt>string(255)</tt>
# *publicity_text*:: <tt>text</tt>
# *proposal_text*::  <tt>text</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *late*::           <tt>boolean</tt>
# *approved*::       <tt>boolean</tt>
# *successful*::     <tt>boolean</tt>
#--
# == Schema Information End
#++
##
class Admin::Proposals::Proposal < ActiveRecord::Base
  belongs_to :call, :class_name => "Admin::Proposals::Call"

  has_many :questions, :through => :answers
  has_many :answers, :as => :answerable
  has_many :team_members, :class_name => "::TeamMember", :as => :teamwork
  has_many :users, :through => :team_members

  accepts_nested_attributes_for :answers, :team_members, :reject_if => :all_blank, :allow_destroy => true

  validates :show_title, :proposal_text, :publicity_text, :presence => true
  validates :team_members, :presence => { :message => "You must add at least one team member" }

  attr_accessible :proposal_text, :publicity_text, :show_title, :answers, :answers_attributes, :team_members, :team_members_attributes, :late, :approved, :successful

  ##
  # Creates an instance of Admin::Answer for every question in the call.
  ##
  def update_answers
    call.questions.each do |question|
      if not questions.all.include? question then
        answer = Admin::Answer.new
        answer.question = question
        answers.push(answer)
      end
    end
  end

  ##
  # Creates a show based on the proposal.
  #
  # Throws an error if the proposal has not been approved.
  ##
  def convert_to_show
    puts self.show_title

    if not self.approved == true then
      abort("This proposal has not been approved")
    end

    @show = Show.new()
    @show.name = self.show_title
    @show.description = self.publicity_text

    @show.slug = @show.name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-')

    self.successful = true

    if not @show.save then
      @show.errors.full_messages.each do |error|
        puts error
      end
      abort("Couldn't save the new show")
    end

    puts "Adding Team Members"
    @show.team_members << self.team_members.collect { |team_member| team_member.dup }

    if not self.save then
      puts "Couldn't set the 'successful' flag on the proposal. This will need to be done manually"
    end

    puts "Created Show:"
    puts "Name: #{@show.name}"
    puts "Slug: #{@show.slug}"
  end
  handle_asynchronously :convert_to_show
end
