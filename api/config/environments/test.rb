require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.secret_key_base = ENV.fetch(
    'SECRET_KEY_BASE',
    'digital_cip_test_secret_key_base_minimum_length_32'
  )

  config.enable_reloading = false
  config.eager_load = true
  config.public_file_server.enabled = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.active_support.deprecation = :stderr
end
