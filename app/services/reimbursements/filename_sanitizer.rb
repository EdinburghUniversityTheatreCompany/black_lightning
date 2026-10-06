module Reimbursements
  ##
  # Receipt attachment filenames for the BACS batch, in the scheme EUSA expects:
  # "<YYYY-MM-DD> <budget> - <description>[ (n)].<ext>".
  module FilenameSanitizer
    # Characters unsafe on at least one OS or in email/SharePoint.
    FORBIDDEN_CHARS = %r{[<>:"/\\|?*\x00-\x1f]}
    # Keeps the whole filename within path limits.
    MAX_DESCRIPTION_LEN = 80

    module_function

    def sanitize_component(text)
      text.to_s.gsub(FORBIDDEN_CHARS, " ").gsub(/\s+/, " ").strip
    end

    def truncate_description(description, max_length: MAX_DESCRIPTION_LEN)
      return description if description.length <= max_length

      # Last space strictly before the cutoff.
      cut_at = description.rindex(" ", max_length - 1)
      return description[0, max_length].rstrip if cut_at.nil? || cut_at < max_length / 2

      description[0, cut_at].rstrip
    end

    # bacs_date is the date of the BACS request, not the receipt's.
    # original_filename supplies only the extension.
    def build_receipt_filename(bacs_date:, budget_name:, description:, original_filename:, index: 1)
      date_part = bacs_date.strftime("%Y-%m-%d")
      budget_part = sanitize_component(budget_name)
      desc_part = truncate_description(sanitize_component(description))
      ext = File.extname(original_filename.to_s).downcase
      ext = ".bin" if ext.empty?
      suffix = index > 1 ? " (#{index})" : ""

      "#{date_part} #{budget_part} - #{desc_part}#{suffix}#{ext}"
    end

    # One file PER payment, so the name has to tell them apart in an inbox. The
    # claim number makes it unique: two payments to one supplier on one day are
    # ordinary.
    def build_international_form_filename(bacs_date:, cost_centre_slug:, payee_name:, auto_number:)
      date_part = bacs_date.strftime("%Y-%m-%d")
      payee_part = truncate_description(sanitize_component(payee_name))
      payee_part = "payee" if payee_part.empty?

      "#{date_part}-#{cost_centre_slug}-international-payment-#{payee_part}-##{auto_number}.xlsx"
    end
  end
end
