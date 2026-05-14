class MetricsController < ApplicationController
  def index
    render plain: AppMetrics.text, content_type: 'text/plain; version=0.0.4'
  end
end
