require 'bunny'

module AppMessaging
  class << self
    def connection
      @connection ||= build_connection
    end

    def channel
      Thread.current[:bunny_channel] ||= connection.create_channel
    end

    def reset!
      Thread.current[:bunny_channel] = nil
      @connection&.close
      @connection = nil
    end

    private

    def build_connection
      conn = Bunny.new(
        ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@rabbitmq:5672'),
        automatically_recover: true,
        recovery_attempts: 10,
        network_recovery_interval: 2.0,
        heartbeat: 30
      )
      conn.start
      conn
    end
  end
end

at_exit { AppMessaging.reset! }
