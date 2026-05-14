module Ingestion
  class CreateDocument
    def initialize(upload:, title: nil, tenant_id: 'default')
      @upload = upload
      @title = title
      @tenant_id = tenant_id
    end

    def call
      validate!
      ActiveRecord::Base.transaction do
        stored = Storage::ObjectStore.put_upload(
          io: @upload.tempfile,
          content_type: @upload.content_type,
          tenant_id: @tenant_id
        )

        @document = Document.create!(
          tenant_id: @tenant_id,
          title: @title || @upload.original_filename,
          content_type: @upload.content_type,
          object_key: stored[:object_key],
          checksum: stored[:checksum],
          byte_size: stored[:byte_size],
          metadata: { filename: @upload.original_filename }
        )

        @document.record_event!(stage: 'upload', from_state: nil, to_state: 'uploaded',
                                message: 'Document accepted', payload: stored)
      end

      enqueue_first_stage
      build_result(success: true, message: 'Document accepted')
    rescue ActiveRecord::RecordInvalid => e
      build_result(success: false, message: e.record.errors.full_messages.join(', '))
    end

    private

    def validate!
      raise ArgumentError, 'upload is required' if @upload.blank?
      raise ArgumentError, 'content_type is required' if @upload.content_type.blank?
    end

    def enqueue_first_stage
      Messaging::Publisher.publish(
        stage: 'ocr',
        document: @document,
        payload: { object_key: @document.object_key }
      )

      AppMetrics::DOCUMENTS_CREATED.increment(labels: { source: 'http' })
    end

    def build_result(success:, message:)
      { success: success, message: message, data: { document: @document } }
    end
  end
end
