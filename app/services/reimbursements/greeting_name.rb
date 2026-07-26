module Reimbursements
  ##
  # The one place that turns a payee into the word an email greets them by —
  # shared so the Notifier's ERB templates and MailboxPollJob's plain-Ruby
  # reply heredocs can't drift apart.
  #
  # A linked account's +first_name+ wins: the payee typed it into their own
  # profile. Person#name is second because PersonLink stores a user's EMAIL
  # there when they have no full name, hence the "@" guard below.
  #
  # Case is deliberately left alone ("PAT PRODUCER" greets as "PAT"):
  # titlecasing mangles McDonald, O'Brien and van der Berg. Titles, compound
  # given names and inverted "Last, First" are likewise not handled.
  module GreetingName
    FALLBACK = "there".freeze

    module_function

    # Never returns blank, so callers can interpolate it straight in.
    def for(person)
      from_user(person) || from_name(person.try(:name)) || FALLBACK
    end

    # +person.user+ is a query, not an attribute read — one indexed row fetch
    # per payee, deliberately not a preload on DatabaseStore#expenses, which
    # the finance grid, the producer portal and every exporter also use. Both
    # callers already make a Graph HTTP call per payee in the same loop.
    def from_user(person)
      user = person.try(:user)
      user && user.first_name.to_s.strip.presence
    end

    # The "@" guard is on the FIRST token, not the whole string, so a name
    # starting with an address can't sneak through on a later word.
    def from_name(name)
      first = name.to_s.strip.split(/\s+/).first.to_s
      return nil if first.blank? || first.include?("@")

      first
    end
  end
end
