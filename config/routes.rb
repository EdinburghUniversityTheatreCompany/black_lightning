ChaosRails::Application.routes.draw do
  
  namespace :admin do resources :staffing_jobs end

  devise_for :users

  resources :shows, :only => [:index, :show]
  resources :news, :only => [:index, :show]
  
  match 'about/' => 'static#about'
  
  match 'admin/' => 'admin#index'
  namespace :admin do
    resources :shows
    resources :news
    resources :editable_blocks, :except => [:show]
    resources :users
    
    resources :staffings do
      collection do
        get 'new_for_show'
        put 'create_for_show'
      end
    end
    
    match '/staffings/:id/show_sign_up' => 'staffings#show_sign_up', :via => :get, :as => :staffing_show_sign_up
    match '/staffings/:job_id/sign_up' => 'staffings#sign_up', :via => :put, :as => :staffing_sign_up
  end
  
  get "/admin/help/markdown"

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  root :to => 'static#home'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
