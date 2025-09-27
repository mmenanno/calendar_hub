# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :calendar_sources do
    member do
      post :sync
      post :force_sync
      get :check_destination
      patch :toggle_active
      patch :toggle_auto_sync
      patch :unarchive
      delete :purge
    end
  end

  post "calendar_sources/sync_all", to: "calendar_sources#sync_all", as: :sync_all_calendar_sources

  resources :calendar_events, only: [:index, :show] do
    member { patch :toggle_sync }
  end

  resource :settings, only: [:show, :edit, :update] do
    post :test_calendar
    post :reset
    post :rotate_credential_key
  end
  resources :event_mappings, only: [:index, :create, :destroy, :edit, :update] do
    collection do
      post :reorder
      post :test
    end
    member do
      patch :toggle
      post :duplicate
    end
  end

  resources :filter_rules, only: [:index, :create, :destroy, :edit, :update] do
    collection do
      post :reorder
      post :test
    end
    member do
      patch :toggle
      post :duplicate
    end
  end

  get "/realtime", to: "realtime#show", as: :realtime
  post "/realtime/ping", to: "realtime#ping", as: :realtime_ping
  namespace :admin do
    resources :jobs, only: [:index] do
      collection do
        post :clear_metrics
      end
    end
  end
  get "/help", to: "help#show", as: :help

  root "calendar_events#index"
end
