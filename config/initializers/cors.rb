ChaosRails::Application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins  'localhost:3000', '127.0.0.1:3000', '/(.+?)\.bedlamtheatre\.co\.uk', 'bedlamtheatre.co.uk', 'api.twitter.com'
    resource '*',
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
