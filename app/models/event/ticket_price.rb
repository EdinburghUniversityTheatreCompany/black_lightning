##
# One priced band of an Event's tickets ("£8 concessions"), stored as a hash in
# the events.ticket_prices JSON column.
##
class Event::TicketPrice
  include ActiveModel::Model
  include ActiveModel::Attributes

  # "other" carries its own label ("Student", "Unwaged").
  CATEGORY_LABELS = {
    "standard" => "Standard",
    "concession" => "Concession",
    "member" => "Member",
    "other" => "Other"
  }.freeze

  CATEGORIES = CATEGORY_LABELS.keys.freeze

  # As a poster writes it: "£10 / £8 concessions / £7 members".
  PRICE_STRING_SUFFIXES = {
    "standard" => nil,
    "concession" => "concessions",
    "member" => "members"
  }.freeze

  attribute :category, :string, default: "standard"
  attribute :label, :string
  attribute :amount, :decimal

  # Not stored: _nested_fields renders a hidden _destroy on every row, so the
  # object must answer to it.
  attribute :_destroy, :boolean, default: false

  # A price as somebody types it: "10", "4.50", "£10".
  READABLE_AMOUNT = /\A\s*£?\s*\d+(?:\.\d{1,2})?\s*\z/

  validates :category, inclusion: { in: CATEGORIES }
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :amount_was_readable

  # Keeps what was typed for the validation: ActiveModel casts "ten" to 0, which
  # reads as Free and sets isAccessibleForFree.
  def amount=(value)
    @raw_amount = value
    super(value.is_a?(String) ? value.sub("£", "").strip : value)
  end

  # A band is never a record. True makes the nested-form controller REMOVE a
  # deleted row rather than hide it, which suits an array rebuilt from the post.
  def new_record?
    true
  end

  def self.from_h(hash)
    hash = hash.to_h.stringify_keys

    new(category: hash["category"], label: hash["label"], amount: hash["amount"])
  end

  def display_label
    return label.presence || CATEGORY_LABELS.fetch("other") if category == "other"

    CATEGORY_LABELS.fetch(category, category.to_s.humanize)
  end

  def free?
    amount&.zero? || false
  end

  # "£10", "£4.50": whole pounds print without pence, as on a poster.
  def formatted_amount
    return nil if amount.nil?
    return "£#{amount.to_i}" if amount == amount.to_i

    format("£%.2f", amount)
  end

  # For the number field: a decimal attribute renders 10 as "10.0".
  def amount_field_value
    return nil if amount.nil?

    amount == amount.to_i ? amount.to_i.to_s : amount.to_s("F")
  end

  # This band's contribution to the derived Event#price string.
  def to_price_string
    suffix = category == "other" ? label.presence : PRICE_STRING_SUFFIXES[category]

    [ formatted_amount, suffix ].compact.join(" ")
  end

  # String keys, so a round trip through MySQL JSON reads the same.
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

  private

  def amount_was_readable
    return unless @raw_amount.is_a?(String)
    return if @raw_amount.blank? || @raw_amount.match?(READABLE_AMOUNT)

    errors.add(:amount, "is not a price")
  end
end
