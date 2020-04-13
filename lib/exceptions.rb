module Exceptions
  module MassMail 
    class MassMailError < StandardError; end
    class AlreadySent < MassMailError; end
    class NoRecipients < MassMailError; end
    class NoSender < MassMailError; end
  end
end
