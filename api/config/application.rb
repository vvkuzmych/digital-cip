require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'

Bundler.require(*Rails.groups)

module DigitalCip
  class Application < Rails::Application
    config.load_defaults 8.0

    config.api_only = true

    config.autoload_lib(ignore: %w[assets tasks])

    config.eager_load_paths << Rails.root.join('lib')

    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc

    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*', headers: :any, methods: %i[get post put patch delete options head]
      end
    end

    config.generators do |g|
      g.test_framework :rspec
      g.skip_routes true
      g.helper false
      g.assets false
      g.view_specs false
    end
  end
end
