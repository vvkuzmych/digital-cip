require 'prometheus/client'
require 'prometheus/client/formats/text'

module AppMetrics
  REGISTRY = Prometheus::Client.registry

  HTTP_REQUESTS = REGISTRY.counter(
    :api_http_requests_total,
    docstring: 'HTTP requests processed by the API',
    labels: %i[method path status]
  )

  HTTP_DURATION = REGISTRY.histogram(
    :api_http_request_seconds,
    docstring: 'HTTP request latency in seconds',
    labels: %i[method path]
  )

  DOCUMENTS_CREATED = REGISTRY.counter(
    :api_documents_created_total,
    docstring: 'Documents accepted for ingestion',
    labels: [:source]
  )

  PUBLISH_TOTAL = REGISTRY.counter(
    :api_messages_published_total,
    docstring: 'Messages published to the ingest exchange',
    labels: [:routing_key]
  )

  def self.text
    Prometheus::Client::Formats::Text.marshal(REGISTRY)
  end
end
