namespace :mail do
  # Sends a test email to the specified address
  task :test, [:email_address] => :environment do |_t, args|
    if args[:email_address].nil?
      raise ArgumentError.new("No test email_address specified. Aborting")
    end

    Tasks::Logic::Mail.send_test_email(args[:email_address])
  end
end
