class ApplicationController < ActionController::API
  before_action :tag_request
  around_action :measure_request

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: 'not_found', message: e.message }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: 'invalid_parameters', message: e.message }, status: :unprocessable_entity
  end

  private

  def tag_request
    @request_id = request.request_id || SecureRandom.uuid
    response.set_header('X-Request-Id', @request_id)
    Rails.logger.tagged(@request_id) if Rails.logger.respond_to?(:tagged)
  end

  def measure_request
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    labels = { method: request.request_method, path: normalized_path }
    AppMetrics::HTTP_DURATION.observe(elapsed, labels: labels)
    AppMetrics::HTTP_REQUESTS.increment(labels: labels.merge(status: response.status.to_s))
  end

  def normalized_path
    (request.path_parameters[:controller] || 'unknown') + '#' + (request.path_parameters[:action] || 'unknown')
  end
end
