ChaosRails::Application.routes.draw do

  namespace :admin do  namespace :proposals do resources :call_question_templates end end

  devise_for :users

  resources :shows,       :only => [:index, :show]
  resources :news,        :only => [:index, :show]
  resources :venues,      :only => [:index, :show]
  resources :attachments, :only => [:show]

  match 'access_denied' => 'static#access_denied'

  match 'about/' => 'static#about'

  match 'admin/' => 'admin#index'
  namespace :admin do
    #The resources pages:
    match 'resources/branding' => 'resources#branding'

    resources :shows do
      member do
        put 'create_questionnaire'
      end
    end

    resources :venues
    resources :news
    resources :editable_blocks, :except => [:show]
    resources :users

    resources :techie_families, :only => [:index]

    resources :staffings do
      collection do
        get 'new_for_show'
        put 'create_for_show'
      end
    end

    match '/staffings/:id/show_sign_up' => 'staffings#show_sign_up', :via => :get, :as => :staffing_show_sign_up
    match '/staffings/:job_id/sign_up' => 'staffings#sign_up', :via => :put, :as => :staffing_sign_up

    namespace :proposals do
      resources :calls do
        member do
          put 'archive'
        end

        resources :proposals do
          member do
            put 'approve'
            put 'reject'
            put 'convert'
          end
        end
      end
    end

    namespace :questionnaires do
      resources :questionnaires, :except => [:new, :create] do
        member do
          get  'answer' => 'questionnaires#answer'
          post 'answer' => 'questionnaires#set_answers'
        end
      end

      resources :questionnaire_templates
    end

    match 'jobs/:action' => 'job_control', :as => "jobs"
  end

  match 'archives(/:start_month/:start_year/:end_month/:end_year)' => 'archives#index', :as => "archives_index"
  match 'archives(/:target)/set_date' => 'archives#set_date', :via => :get
  namespace :archives do
    match 'shows(/:start_month/:start_year/:end_month/:end_year)' => 'shows#index', :as => :shows_index
    match 'proposals(/:start_month/:start_year/:end_month/:end_year)' => 'proposals#index', :as => :proposals_index
  end

  get "/admin/help/markdown"

  # ERROR PAGES
  match '/404' => 'static#render_404'

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
