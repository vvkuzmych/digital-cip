module Storage
  class ObjectStore
    def self.put_upload(io:, content_type:, tenant_id: 'default')
      new.put_upload(io: io, content_type: content_type, tenant_id: tenant_id)
    end

    def put_upload(io:, content_type:, tenant_id:)
      key = "raw/#{tenant_id}/#{Time.current.utc.strftime('%Y/%m/%d')}/#{SecureRandom.uuid}"
      checksum = Digest::SHA256.new
      bytes = 0

      buffer = StringIO.new
      io.rewind
      while (chunk = io.read(64 * 1024))
        checksum.update(chunk)
        bytes += chunk.bytesize
        buffer.write(chunk)
      end
      buffer.rewind

      AppStorage.client.put_object(
        bucket: AppStorage.bucket,
        key: key,
        body: buffer,
        content_type: content_type
      )

      { object_key: key, checksum: checksum.hexdigest, byte_size: bytes }
    end

    def self.presigned_url(key, expires_in: 600)
      Aws::S3::Presigner.new(client: AppStorage.client).presigned_url(
        :get_object,
        bucket: AppStorage.bucket,
        key: key,
        expires_in: expires_in
      )
    end
  end
end
