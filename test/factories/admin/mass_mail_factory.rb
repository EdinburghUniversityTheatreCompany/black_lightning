FactoryBot.define do
  factory :draft_mass_mail, class: MassMail do
    subject { generate(:random_string) }
    body { generate(:random_string) }

    draft { true }

    send_date { DateTime.current.advance(days: 1) }

    factory :sent_mass_mail do
      draft { false }
    end
  end
end
