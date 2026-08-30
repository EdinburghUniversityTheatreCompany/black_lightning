require "test_helper"

class MassMailerTest < ActionMailer::TestCase
  # An email has no base URL, so a relative href is dead on arrival: the recipient's mail client
  # either ignores it or resolves it against its own domain. The markdown renderer rewrites links
  # to our own host into paths, which is right on the web and wrong here.
  test "a link to our own site stays absolute in a mass mail" do
    mail = deliver("Tickets are on sale [now](https://www.bedlamtheatre.co.uk/shows).")

    assert_includes mail.html_part.decoded, 'href="https://www.bedlamtheatre.co.uk/shows"'
    assert_not_includes mail.html_part.decoded, 'href="/shows"'
  end

  test "an apex link also stays absolute in a mass mail" do
    mail = deliver("See [what's on](https://bedlamtheatre.co.uk/events).")

    assert_includes mail.html_part.decoded, 'href="https://bedlamtheatre.co.uk/events"'
  end

  # The other half of the normalisation is still right in an email: a target typed without a
  # scheme is broken everywhere, not just on the web.
  test "a schemeless link is still made absolute in a mass mail" do
    mail = deliver("Our friends at [the Improverts](theimproverts.co.uk) are on tonight.")

    assert_includes mail.html_part.decoded, 'href="https://theimproverts.co.uk"'
  end

  test "an external link is untouched in a mass mail" do
    mail = deliver("Read the [wiki](https://wiki.bedlamtheatre.co.uk/history).")

    assert_includes mail.html_part.decoded, 'href="https://wiki.bedlamtheatre.co.uk/history"'
  end

  private

  def deliver(body)
    mass_mail = MassMail.new(subject: "Newsletter", body: body)
    recipient = FactoryBot.create(:user)

    MassMailer.send_mail(mass_mail, recipient)
  end
end
