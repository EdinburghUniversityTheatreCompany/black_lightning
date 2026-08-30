##
# One priced band of an Event's tickets: "£8 concessions".
#
# Stored as a plain hash inside the events.ticket_prices JSON column rather than
# in a table of its own, and wrapped here so callers get validation, a written
# label and an exact amount instead of whatever the JSON happened to hold.
#
# Event#ticket_prices_attributes= accepts the same nested-attributes shape an
# association would, so the existing nested-form UI drives these unchanged.
##
class Event::TicketPrice
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Written labels first, values derived from them, as EventOccurrence does.
  # "other" carries its own label instead ("Student", "Unwaged", ...).
  CATEGORY_LABELS = {
    "standard" => "Standard",
    "concession" => "Concession",
    "member" => "Member",
    "other" => "Other"
  }.freeze

  CATEGORIES = CATEGORY_LABELS.keys.freeze

  # How each band reads in the derived Event#price string. Standard carries no
  # suffix: "£10 / £8 concessions / £7 members" is how a poster writes it.
  PRICE_STRING_SUFFIXES = {
    "standard" => nil,
    "concession" => "concessions",
    "member" => "members"
  }.freeze

  attribute :category, :string, default: "standard"
  attribute :label, :string
  attribute :amount, :decimal

  # Not stored. shared/form/sections/_nested_fields renders a hidden _destroy on
  # every row, so the object has to answer to it or the form raises.
  attribute :_destroy, :boolean, default: false

  validates :category, inclusion: { in: CATEGORIES }
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # A band is never a record of its own -- it is one entry in a JSON array, keyed
  # by nothing but its position. Answering true is also what makes the nested-form
  # controller REMOVE a deleted row from the DOM rather than hide it and set
  # _destroy, which is the behaviour that suits an array rebuilt from what posts.
  def new_record?
    true
  end

  def self.from_h(hash)
    hash = hash.respond_to?(:to_h) ? hash.to_h : {}

    new(category: hash["category"] || hash[:category],
        label: hash["label"] || hash[:label],
        amount: hash["amount"] || hash[:amount])
  end

  # What this band is called on screen.
  def display_label
    return label.presence || CATEGORY_LABELS.fetch("other") if category == "other"

    CATEGORY_LABELS.fetch(category, category.to_s.humanize)
  end

  def free?
    amount&.zero? || false
  end

  # "£10", "£4.50" -- a whole number of pounds prints without the pence, because
  # that is how every price on a poster is written.
  def formatted_amount
    return nil if amount.nil?
    return "£#{amount.to_i}" if amount == amount.to_i

    format("£%.2f", amount)
  end

  # What the number field should show. A decimal attribute renders 10 as "10.0",
  # which is not what anyone typed.
  def amount_field_value
    return nil if amount.nil?

    amount == amount.to_i ? amount.to_i.to_s : amount.to_s("F")
  end

  # This band's contribution to the derived Event#price string.
  def to_price_string
    suffix = category == "other" ? label.presence : PRICE_STRING_SUFFIXES[category]

    [ formatted_amount, suffix ].compact.join(" ")
  end

  # Written back into the JSON column. String keys, so a round trip through
  # MySQL's JSON type reads the same way it was written.
  def to_h
    { "category" => category, "label" => label.presence, "amount" => amount&.to_s("F") }
  end

  def ==(other)
    other.is_a?(self.class) && to_h == other.to_h
  end
  alias eql? ==

  def hash
    to_h.hash
  end
end
