# RubyLLM configuration for the reimbursements Gemini call sites (receipt
# Extractor and the operator AiChecker). Both build their chats through
# RubyLLM.chat, which reads this global config. The key may be absent in some
# environments (CI, a collaborator without secrets); that is not an error here —
# a real call then fails at request time and each call site degrades gracefully
# (the Extractor returns ok?: false, the AiChecker returns an "error" verdict).
#
# Wrapped in +to_prepare+ so the app constant (Reimbursements::Settings) is
# resolvable — plain initializers run before the autoloader is ready.
require "ruby_llm/schema" # RubyLLM::Schema (structured output) isn't auto-required

Rails.application.config.to_prepare do
  RubyLLM.configure do |config|
    config.gemini_api_key = Reimbursements::Settings.gemini_api_key
    config.request_timeout = 120
  end
end
