module Reimbursements
  ##
  # The one place that turns a payee into the word an email greets them by.
  #
  # Both surfaces route through here so the rule can never drift between them:
  # the Notifier's ERB templates (via their call sites, which pass the derived
  # string — the Notifier itself stays ActiveRecord-free) and MailboxPollJob's
  # plain-Ruby reply heredocs.
  #
  # A linked account's own +first_name+ wins: the payee typed it into their
  # profile, so it is the name they answer to. Person#name is a registry label
  # an operator may have typed — or, for a user with no full name, literally
  # their email address (PersonLink#create_person), which is why an "@" in the
  # leading word falls through to the generic greeting rather than opening a
  # message with "Hi alice@example.com,".
  #
  # Deliberately NOT handled, because every fix costs more than it buys:
  #   * case ("PAT PRODUCER" greets as "PAT") — titlecasing mangles McDonald,
  #     O'Brien and van der Berg, so we render the name as it was written;
  #   * titles ("Dr Jane Smith" -> "Dr") — needs a list that is always partial;
  #   * compound given names ("Jo Ann Smith" -> "Jo") — undecidable without a
  #     name database;
  #   * inverted "Last, First" — a comma heuristic misfires on "Smith & Co".
  module GreetingName
    # What we greet with when there is no usable name.
    FALLBACK = "there".freeze

    module_function

    # Person (or anything name-shaped, or nil) in, greeting word out. Never
    # blank, so callers can interpolate it straight into a template.
    def for(person)
      from_user(person) || from_name(person.try(:name)) || FALLBACK
    end

    # nil when the payee has no linked user account, or has one with a blank
    # first_name.
    #
    # +person.user+ is a query, not an attribute read — one extra indexed row
    # fetch per payee. That is deliberate rather than a preload on
    # DatabaseStore#expenses: that preload is shared by the finance grid, the
    # producer portal and every exporter, which would all pay for a greeting
    # only two email paths use. Both callers already make a Graph HTTP call
    # per payee in the same loop, which dwarfs it.
    def from_user(person)
      user = person.try(:user)
      user && user.first_name.to_s.strip.presence
    end

    # nil when there is no usable leading word, so +for+ falls back. The "@"
    # guard is on the FIRST token, not the whole string, so a name that starts
    # with an address can't sneak one through on the strength of a later word.
    def from_name(name)
      first = name.to_s.strip.split(/\s+/).first.to_s
      return nil if first.blank? || first.include?("@")

      first
    end
  end
end
