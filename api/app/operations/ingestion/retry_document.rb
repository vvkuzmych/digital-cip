module Ingestion
  class RetryDocument
    def initialize(document)
      @document = document
    end

    def call
      stage = resume_stage
      return failure('Document is in a terminal success state') unless stage

      ActiveRecord::Base.transaction do
        @document.update!(failure_reason: nil, retry_count: @document.retry_count + 1)
        @document.record_event!(stage: stage, to_state: @document.status,
                                actor: 'operator', message: 'Manual retry requested')
      end

      Messaging::Publisher.publish(stage: stage, document: @document,
                                   payload: { object_key: @document.object_key },
                                   attempt: 1)

      { success: true, message: "Re-enqueued for #{stage}", data: { document: @document } }
    end

    private

    def resume_stage
      case @document.status
      when 'failed', 'uploaded', 'ocr_processing' then 'ocr'
      when 'ocr_completed', 'chunking' then 'chunk'
      when 'chunked', 'embedding' then 'embed'
      end
    end

    def failure(msg)
      { success: false, message: msg, data: { document: @document } }
    end
  end
end
