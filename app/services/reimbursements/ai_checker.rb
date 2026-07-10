module Reimbursements
  ##
  # AI-powered expense checker. Sends each expense's receipts and metadata to
  # Gemini (through RubyLLM, sharing the gem with the receipt Extractor) and
  # returns a validated verdict: does the receipt amount match, does the
  # description match, is the budget appropriate, and — when the receipt itemises
  # VAT — is the ex-VAT amount consistent.
  #
  # Ported from bedlam-bacs `ai_checker.py`. For an ordinary reimbursement the
  # payee name is deliberately NOT checked against the receipt (members pay
  # suppliers personally and claim it back, so a name mismatch is normal). The
  # exception is a direct third-party payment (a payee override): there the money
  # goes straight to a supplier, so the checker DOES verify the override name and
  # bank details against the invoice.
  #
  # Never raises: any failure (no key, network, bad response) becomes an "error"
  # verdict so the Review queue keeps working. +chat_builder+ is the injection
  # seam — tests pass a fake chat so no real Gemini call is made.
  class AiChecker
    MODEL = "gemini-2.5-flash".freeze

    Result = Struct.new(:status, :comment, :suggested_budget, :checked_at, keyword_init: true)

    # Structured verdict the model must return. "error" is never a value the
    # model picks — it's reserved for exceptions captured by #check.
    SCHEMA = RubyLLM::Schema.create do
      string :status, enum: %w[pass fail],
             description: "pass if the receipt matches the submitted details, fail if anything is wrong or suspicious"
      string :comment, required: false,
             description: "Brief note: what is wrong on a fail, or an optional informational note on a pass"
      string :suggested_budget, required: false,
             description: "A more suitable budget category name, if the chosen one looks wrong"
    end

    def initialize(chat_builder: nil)
      @chat_builder = chat_builder || -> { RubyLLM.chat(model: MODEL) }
    end

    # expense: a Reimbursements::Expense; budgets: [Budget] shown to the model so
    # a suggested_budget names a real category. Returns a Result; never raises.
    def check(expense, budgets = [])
      return error_result("No receipts attached — cannot perform AI check.") if expense.receipts.empty?

      response = @chat_builder.call
                             .with_schema(SCHEMA)
                             .ask(prompt(expense, budgets), with: expense.receipts.map(&:url))
      verdict(response.content)
    rescue RubyLLM::Error => e
      error_result("Gemini request failed: #{e.message}")
    rescue StandardError => e
      error_result(e.message)
    end

    private

    def verdict(data)
      data = {} unless data.is_a?(Hash)
      status = data["status"] == "pass" ? "pass" : "fail"
      comment = data["comment"].to_s
      suggested = data["suggested_budget"].to_s

      # Fold the suggestion into the comment so it surfaces in the UI without a
      # separate Airtable field. A suggestion can accompany a passing verdict,
      # so fold it in regardless of status.
      comment = "#{comment} Suggested budget: #{suggested}".strip if suggested.present?

      Result.new(status: status, comment: comment, suggested_budget: suggested, checked_at: Time.current)
    end

    def error_result(message)
      Result.new(status: "error", comment: message.to_s, suggested_budget: "", checked_at: Time.current)
    end

    def prompt(expense, budgets)
      <<~PROMPT.strip
        You are reviewing an expense claim. Check whether the attached receipts match the submitted details.

        Submitted details:
        - Payee: #{expense.person&.name.presence || '(unknown)'}
        - Amount (incl. VAT): £#{expense.amount}
        - Amount (excl. VAT): £#{expense.amount_excl_vat || 'unknown'}
        - Budget category: #{expense.budget&.name.presence || '(none)'}
        - Description: #{expense.description.presence || '(no description)'}
        #{budget_list_block(budgets)}
        About the payee: the payee is whoever will receive the bank transfer. People frequently pay \
        suppliers out of their own pocket and claim reimbursement, or submit invoices on behalf of \
        their show, so the payee's name often differs from the merchant, supplier, or account holder \
        named on the receipt or in the description. This is normal and expected. Payee identity and \
        bank details are verified separately by the finance team — do NOT respond status=fail solely \
        because of a name mismatch between the payee and the receipt or description.

        Please check:
        1. Do the receipt(s) show the same or similar amount?
        2. Does the description match what is on the receipt?
        3. Is the budget category appropriate for this type of expense?
        4. VAT: if the receipt explicitly itemises VAT (a VAT amount/rate with a VAT registration \
        number), the amount excl. VAT should equal the total minus that VAT. If the receipt itemises \
        VAT but the submitted excl.-VAT amount is missing or clearly wrong, flag it. If the receipt \
        does not itemise VAT, the excl.-VAT amount may equal the total — that is fine.

        If everything looks correct, respond with status=pass. You may still include a brief \
        informational note in comment if something is worth a human glance without being a problem in \
        itself; otherwise leave comment empty.
        If anything is wrong or suspicious about the amount, description, budget, or VAT, respond with \
        status=fail and explain specifically what is wrong.
        If the budget seems incorrect, put a more suitable budget in suggested_budget.
        #{override_block(expense)}
      PROMPT
    end

    # Only rendered when budgets are supplied, so the "pick from these / propose a
    # new one" guidance never references a list that isn't in the prompt.
    def budget_list_block(budgets)
      return "" if budgets.blank?

      names = budgets.map { |b| "- #{b.name}" }.join("\n")
      <<~BLOCK

        Existing budget categories:
        #{names}
        When you put a value in suggested_budget, choose one of these existing categories. If none of \
        them is a good fit, you may propose a NEW category: set suggested_budget to the proposed name \
        and state clearly in comment that it does not exist yet and would need to be created.
      BLOCK
    end

    def override_block(expense)
      return "" unless expense.payee_override?

      <<~BLOCK

        IMPORTANT — DIRECT PAYMENT TO A THIRD PARTY:
        This expense will NOT be paid to the submitter. It is a direct payment to a third party (e.g. \
        paying a supplier's or photographer's invoice), with these override payment details:
        - Payee name: #{expense.payee_name_override.presence || '(not overridden)'}
        - Sort code: #{expense.sort_code_override.presence || '(not overridden)'}
        - Account number: #{expense.account_number_override.presence || '(not overridden)'}

        Because the money goes straight to this third party, the payee identity DOES matter here (this \
        overrides the "do not check the payee name" guidance above). Check the attached invoice/receipt \
        and verify that the payee name and bank details above match the supplier, business, or account \
        holder named on the invoice. If they match, this is fine. If the name or bank details do NOT \
        match anything on the invoice, respond status=fail and say exactly what does not match, so a \
        human can check before payment.
      BLOCK
    end
  end
end
