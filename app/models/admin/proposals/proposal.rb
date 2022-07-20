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
# *publicity_text*:: <tt>text(65535)</tt>
# *proposal_text*::  <tt>text(65535)</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *late*::           <tt>boolean</tt>
# *approved*::       <tt>boolean</tt>
# *successful*::     <tt>boolean</tt>
#--
# == Schema Information End
#++
class Admin::Proposals::Proposal < ApplicationRecord
  include LabelHelper
  has_paper_trail

  validates :show_title, :proposal_text, :publicity_text, :call_id, presence: true

  belongs_to :call, class_name: 'Admin::Proposals::Call'
  
  has_one :event, class_name: 'Event'

  has_many :answers, as: :answerable
  has_many :questions, through: :answers
  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :restrict_with_error
  has_many :users, through: :team_members

  accepts_nested_attributes_for :answers, :team_members, reject_if: :all_blank, allow_destroy: true

  # Reading is completely managed by ability.rb because it is so complicated and dependent on the call.
  DISABLED_PERMISSIONS = %w[read].freeze

  ##
  # Creates an instance of Admin::Answer for every question in the call.
  ##
  def instantiate_answers!
    call.questions&.each do |question|
      next if question.answers.where(answerable: self).any?

      answer = Admin::Answer.new
      answer.question = question

      answers.push(answer)
    end
  end

  ##
  # Generates a list of html labels with info about the proposal.
  ##
  def labels(pull_right)
    labels = []

    labels << case successful
              when true
                generate_label(:success, 'Successful', pull_right)
              when false
                generate_label(:danger, 'Unsuccessful', pull_right)
              else
                case approved
                when true
                  generate_label(:success, 'Approved', pull_right)
                when false
                  generate_label(:danger, 'Rejected', pull_right)
                else
                  generate_label(:warning, 'Waiting for Approval', pull_right)
                end
              end

    labels << generate_label(:danger, 'Late', pull_right) if late
    labels << generate_label(:danger, 'Has Debtors', pull_right) if has_debtors

    if pull_right
      # Bcause the highest float-right will be farthest to the right, the order has to be reversed.
      return "#{labels.reverse.join("\n")}\n<div style=\"clear: both;\"></div>".html_safe
    else
      return labels.join("\n").html_safe
    end
  end

  ##
  # returns true if any users associated with the proposal are in debt with debts starting before the creation of this proposal
  ##
  def has_debtors
    return users.in_debt(call.editing_deadline.to_date).any?
  end

  ##
  # Creates a show based on the proposal.
  #
  # Throws an error if the proposal has not been approved.
  ##
  def convert_to_show
    unless successful
      p "The proposal #{show_title} was not succesful and cannot be converted to a show"
      raise ArgumentError, 'This proposal was not successful'
    end

    p "Converting #{show_title} from proposal to show"

    @show = Show.new
    @show.name = show_title
    @show.publicity_text = publicity_text

    @show.slug = @show.name&.to_url

    @show.author = 'TBC'
    @show.price = 'TBC'

    @show.start_date = Date.current
    @show.end_date = Date.current
    @show.is_public = false

    venue = Venue.find_by(name: 'Unknown').presence || Venue.where('name like ?', '%unknown').first.presence || Venue.find_by(name: 'Bedlam Theatre').presence || Venue.where('name like ?', '%Bedlam%').first.presence

    raise(ActiveRecord::RecordNotSaved, "Could not save the new show based on #{show_title}. Could not find a Venue with a name resembling 'Unknown', resembling 'Bedlam Theatre' or with a name that contains 'Bedlam'.") if venue.nil?

    @show.venue = venue

    unless @show.save
      @show.errors.full_messages.each do |error|
        p error
      end
      p 'Converting the proposal to a show failed for the above reasons.'
      raise ActiveRecord::RecordNotSaved, "Could not save the new show based on #{show_title}. #{@show.errors.full_messages.join(' ,')}"
    end

    p 'Adding Team Members'
    @show.team_members << team_members.collect(&:dup)

    @show.proposal = self

    self.successful = true

    # Highly unlikely situation, but you never know. I cannot deliberately cause it.
    # :nocov:
    unless save
      message = "Couldn't set the 'successful' flag on the proposal, couldn't add the team members to the show, or couldn't set the show proposal to this one. This will need to be done manually."
      p message
      raise ActiveRecord::RecordNotSaved, message
    end
  # :nocov:

    p 'Created Show:'
    p "Name: #{@show.name}"
    p "Slug: #{@show.slug}"
  end
  handle_asynchronously :convert_to_show
end
