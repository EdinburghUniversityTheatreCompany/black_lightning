ChaosRails::Application.config.middleware.use Rack::Cors do
  allow do
    origins  '*' # /(.+?)\.bedlamtheatre\.co\.uk$/
    resource '*',
             headers: :any,
             methods: [:get, :put, :create, :delete, :options]
  end
end
