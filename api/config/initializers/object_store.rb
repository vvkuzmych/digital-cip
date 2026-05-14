require 'aws-sdk-s3'

module AppStorage
  class << self
    def client
      @client ||= Aws::S3::Client.new(
        endpoint: ENV.fetch('MINIO_ENDPOINT', 'http://minio:9000'),
        access_key_id: ENV.fetch('MINIO_ROOT_USER', 'minio'),
        secret_access_key: ENV.fetch('MINIO_ROOT_PASSWORD', 'minio12345'),
        region: ENV.fetch('MINIO_REGION', 'us-east-1'),
        force_path_style: true
      )
    end

    def bucket
      ENV.fetch('MINIO_BUCKET', 'documents')
    end
  end
end
