module CalendarHelper
  GOOGLE_DOMAINS    = %w[gmail.com googlemail.com].freeze
  MICROSOFT_DOMAINS = %w[ed.ac.uk sms.ed.ac.uk outlook.com hotmail.com live.com msn.com].freeze

  def calendar_instructions_for(email)
    domain = email.to_s.split("@").last.to_s.downcase

    if GOOGLE_DOMAINS.include?(domain)
      render_google_instructions
    elsif MICROSOFT_DOMAINS.include?(domain)
      render_microsoft_instructions
    else
      render_all_instructions
    end
  end

  private

  def render_google_instructions
    content_tag(:div, class: "calendar-instructions") do
      content_tag(:p) do
        concat content_tag(:strong, "Google Calendar: ")
        concat "Open Google Calendar → click the "
        concat content_tag(:strong, "+ next to 'Other calendars'")
        concat " → select "
        concat content_tag(:em, "From URL")
        concat " → paste the https:// link above."
      end
    end
  end

  def render_microsoft_instructions
    content_tag(:div, class: "calendar-instructions") do
      content_tag(:p) do
        concat content_tag(:strong, "Outlook / Microsoft 365: ")
        concat "Open Outlook → "
        concat content_tag(:strong, "Add calendar")
        concat " → "
        concat content_tag(:em, "Subscribe from web")
        concat " → paste the https:// link above."
      end
    end
  end

  def render_all_instructions
    content_tag(:div, class: "calendar-instructions") do
      concat content_tag(:p) {
        concat content_tag(:strong, "Google Calendar: ")
        concat "Open Google Calendar → + next to 'Other calendars' → From URL → paste the https:// link."
      }
      concat content_tag(:p) {
        concat content_tag(:strong, "Outlook / Microsoft 365: ")
        concat "Open Outlook → Add calendar → Subscribe from web → paste the https:// link."
      }
      concat content_tag(:p) {
        concat content_tag(:strong, "Apple Calendar: ")
        concat "Click the webcal:// link above — macOS/iOS will prompt you to subscribe."
      }
    end
  end
end
