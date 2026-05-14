require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.secret_key_base = ENV.fetch('SECRET_KEY_BASE')

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_level = ENV.fetch('LOG_LEVEL', 'info').to_sym
  config.log_tags = [:request_id]
  config.active_support.deprecation = :notify
  config.force_ssl = false
end
