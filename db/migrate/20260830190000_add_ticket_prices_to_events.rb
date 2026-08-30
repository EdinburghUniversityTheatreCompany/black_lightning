class AddTicketPricesToEvents < ActiveRecord::Migration[8.1]
  def change
    # Nullable, and read through Event#ticket_prices which treats nil as an empty
    # list: MySQL will not take a literal default on a JSON column, and every one
    # of the ~3000 existing rows starts with nothing in it.
    add_column :events, :ticket_prices, :json

    # Parsed out of the archive's "+ £1 booking fee on the door" suffixes. Kept
    # separate from the bands because it is not a band -- it is a surcharge on
    # every one of them.
    add_column :events, :booking_fee, :decimal, precision: 8, scale: 2
  end
end
