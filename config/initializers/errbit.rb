Airbrake.configure do |config|
  config.api_key = 'e0b64dbf1b19d4e671e08566942c8b5e'
  config.host    = 'errbit.mercuric.co.uk'
  config.port    = 80
  config.secure  = config.port == 443
end