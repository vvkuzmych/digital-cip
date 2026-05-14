class HealthController < ApplicationController
  def liveness
    render json: { status: 'ok' }
  end

  def readiness
    checks = {
      db: db_ok?,
      redis: redis_ok?,
      rabbit: rabbit_ok?,
      storage: storage_ok?
    }
    status = checks.values.all? ? :ok : :service_unavailable
    render json: { status: status == :ok ? 'ready' : 'degraded', checks: checks }, status: status
  end

  private

  def db_ok?
    ActiveRecord::Base.connection.execute('SELECT 1') && true
  rescue StandardError
    false
  end

  def redis_ok?
    REDIS_POOL.with { |r| r.ping == 'PONG' }
  rescue StandardError
    false
  end

  def rabbit_ok?
    AppMessaging.connection.open?
  rescue StandardError
    false
  end

  def storage_ok?
    AppStorage.client.head_bucket(bucket: AppStorage.bucket) && true
  rescue StandardError
    false
  end
end
