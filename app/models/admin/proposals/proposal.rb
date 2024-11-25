##
# Represents a proposal.
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

  validates :show_title, :proposal_text, :publicity_text, :call_id, :status, presence: true

  enum :status,
    awaiting_approval: 0,
    approved: 1,
    rejected: 2,
    successful: 3,
    unsuccessful: 4

  belongs_to :call, class_name: 'Admin::Proposals::Call'

  has_one :event, class_name: 'Event'

  has_many :answers, as: :answerable
  has_many :questions, through: :answers
  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :restrict_with_error
  has_many :users, through: :team_members

  accepts_nested_attributes_for :answers, :team_members, reject_if: :all_blank, allow_destroy: true

  after_initialize :set_default_proposal_text

  normalizes :show_title, with: ->(show_title) { show_title&.strip }

  # Reading is completely managed by ability.rb because it is so complicated and dependent on the call.
  DISABLED_PERMISSIONS = %w[read].freeze

  def self.ransackable_attributes(auth_object = nil)
    %w[approved proposal_text publicity_text show_title successful]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[call users]
  end

  # Creates an instance of Admin::Answer for every question in the call.
  def instantiate_answers!
    call.questions&.each do |question|
      next if question.answers.where(answerable: self).any?

      answer = Admin::Answer.new
      answer.question = question

      answers.push(answer)
    end
  end

  #
  def formatted_status
    return status.to_s.titleize
  end

  #
  def label_css_class
    case status
    when 'awaiting_approval'
      :warning
    when 'approved'
      :info
    when 'successful'
      :success
    when 'rejected', 'unsuccessful'
      :danger
    end
  end

  # Generates a list of html labels with info about the proposal.
  def labels(pull_right)
    labels = []

    labels << generate_label(label_css_class, formatted_status)
    labels << generate_label(:danger, 'Late') if late
    labels << generate_label(:danger, 'Has Debtors') if has_debtors

    labels_html = labels.join("\n").html_safe

    # Wrap the whole list of labels in a float right so that the margins stay preserved.
    return "<div class=\"float-right\">#{labels_html}</div>".html_safe if pull_right

    return labels_html
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
    unless successful?
      p "The proposal #{show_title} was not successful and cannot be converted to a show"
      raise ArgumentError, 'This proposal was not successful'
    end

    p "Converting #{show_title} from proposal to show"

    @show = Show.new
    @show.name = show_title
    @show.publicity_text = publicity_text

    @show.slug = "#{@show.name&.to_url}-#{Date.current.year}"

    # Check if the slug already exists on an event
    if Event.find_by(slug: @show.slug).present?
      p "Found a show with the same slug, which is #{@show.slug}."
      original_slug = @show.slug

      max_number = 30
      # If so, append a number, and keep upping it until this Event's slug is unique.
      for number in 2..max_number do
        @show.slug = "#{original_slug}-#{number}"

        # If it hits 30, something has gone very very wrong, as there would be 30 duplicate events in the same year, so throw an error.
        raise(ActiveRecord::RecordNotSaved, "The number appended at the end of the slug has hit the maximum when converting the proposal \"#{show_title}\" with id \"#{id}\". Check what other events there are with their slug starting with \"#{original_slug}\".") if number == max_number

        # Break if there are no duplicate events with this slug anymore.
        break unless Event.find_by(slug: @show.slug).present?
      end
    end

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

  private

  def set_default_proposal_text
    return if !has_attribute?(:proposal_text) || proposal_text.present?

    self.proposal_text = Admin::EditableBlock.find_by(name: 'Proposals - Proposal Text Default').try(:content) || ''
  end
end
