require 'redis'
require 'connection_pool'

REDIS_POOL = ConnectionPool.new(size: 10, timeout: 5) do
  Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
end
