require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.secret_key_base = ENV.fetch(
    'SECRET_KEY_BASE',
    'digital_cip_development_secret_key_base_min_32_chars_'
  )

  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.active_record.migration_error = false
  config.active_record.verbose_query_logs = true

  config.active_support.deprecation = :log

  config.hosts.clear
end
