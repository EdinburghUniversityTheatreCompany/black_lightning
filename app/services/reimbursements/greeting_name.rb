module Reimbursements
  # The one derivation of the word an email greets a payee by, shared by the Notifier's ERB
  # templates and MailboxPollJob's reply heredocs so they cannot drift.
  #
  # A linked account's +first_name+ wins (the payee typed it). Person#name is second, but
  # PersonLink stores the user's EMAIL there when they have no full name, hence the "@" guard.
  # Case is deliberately left alone ("PAT PRODUCER" greets as "PAT"): titlecasing mangles
  # McDonald, O'Brien and van der Berg. Titles, compound given names and "Last, First" are not handled.
  module GreetingName
    FALLBACK = "there".freeze

    module_function

    # Never returns blank, so callers can interpolate it straight in.
    def for(person)
      from_user(person) || from_name(person.try(:name)) || FALLBACK
    end

    # +person.user+ is a query, deliberately not a preload on DatabaseStore#expenses (shared with
    # the finance grid, producer portal and exporters); both callers already make a Graph call
    # per payee in the same loop.
    def from_user(person)
      user = person.try(:user)
      user && user.first_name.to_s.strip.presence
    end

    # The "@" guard reads the FIRST token, the only one used.
    def from_name(name)
      first = name.to_s.strip.split(/\s+/).first.to_s
      return nil if first.blank? || first.include?("@")

      first
    end
  end
end
