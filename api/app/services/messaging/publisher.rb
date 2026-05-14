require 'oj'
require 'ulid'

module Messaging
  class Publisher
    EXCHANGE_NAME = 'ingest'.freeze

    def self.publish(stage:, document:, payload: {}, attempt: 1)
      new.publish(stage: stage, document: document, payload: payload, attempt: attempt)
    end

    def publish(stage:, document:, payload: {}, attempt: 1)
      routing_key = "ingest.#{stage}"
      envelope = build_envelope(stage: stage, document: document, payload: payload, attempt: attempt)

      exchange.publish(
        Oj.dump(envelope, mode: :compat),
        routing_key: routing_key,
        persistent: true,
        content_type: 'application/json',
        message_id: envelope[:message_id],
        headers: {
          'x-idempotency-key' => envelope[:idempotency_key],
          'x-attempt' => attempt,
          'x-stage' => stage,
          'x-document-id' => document.id
        }
      )

      AppMetrics::PUBLISH_TOTAL.increment(labels: { routing_key: routing_key })
      Rails.logger.info(
        event: 'message.published',
        routing_key: routing_key,
        message_id: envelope[:message_id],
        document_id: document.id,
        attempt: attempt
      )

      envelope
    end

    private

    def exchange
      @exchange ||= AppMessaging.channel.topic(EXCHANGE_NAME, durable: true)
    end

    def build_envelope(stage:, document:, payload:, attempt:)
      {
        message_id: ULID.generate,
        idempotency_key: "#{document.id}:#{stage}",
        trace_id: SecureRandom.uuid,
        stage: stage,
        document_id: document.id,
        tenant_id: document.tenant_id,
        attempt: attempt,
        published_at: Time.current.iso8601,
        payload: payload
      }
    end
  end
end
