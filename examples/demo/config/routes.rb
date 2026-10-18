# frozen_string_literal: true

Rails.application.routes.draw do
  root "pages#show"
  get "/up", to: "pages#health"
end
