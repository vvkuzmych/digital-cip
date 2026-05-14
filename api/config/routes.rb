Rails.application.routes.draw do
  get '/healthz', to: 'health#liveness'
  get '/readyz',  to: 'health#readiness'
  get '/metrics', to: 'metrics#index'

  namespace :api do
    namespace :v1 do
      resources :documents, only: %i[index show create] do
        member do
          post :retry
        end
        resources :chunks, only: %i[index], controller: 'document_chunks'
      end
    end
  end

  root to: ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"service":"digital-cip"}']] }
end
