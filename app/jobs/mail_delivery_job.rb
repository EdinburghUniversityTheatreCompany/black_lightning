class MailDeliveryJob < ApplicationJob
  queue_as :mailers

  # Inherits SMTP retry logic from ApplicationJob:
  # - Net::SMTPFatalError (5xx) and Net::SMTPServerBusy (450 rate limits)
  # - 10 attempts with polynomial backoff spanning ~30 minutes

  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    mailer_class = mailer.constantize
    mailer_class = mailer_class.with(params) if params
    message = if kwargs
                mailer_class.public_send(mail_method, *args, **kwargs)
    else
                mailer_class.public_send(mail_method, *args)
    end
    message.send(delivery_method)
  end
end
