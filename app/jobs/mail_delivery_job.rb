class MailDeliveryJob < ApplicationJob
  queue_as :mailers

  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    Honeybadger.context(mailer: mailer, mail_method: mail_method)

    mailer_class = mailer.constantize
    mailer_class = mailer_class.with(params) if params
    mailer_class.public_send(mail_method, *args, **kwargs).send(delivery_method)
  end
end
