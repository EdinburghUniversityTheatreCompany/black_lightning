ChaosRails::Application.routes.draw do

  get "seasons/show"

  devise_for :users

  resources :shows,       :only => [:index, :show]
  resources :workshops,   :only => [:index, :show]
  resources :news,        :only => [:index, :show]
  resources :venues,      :only => [:index, :show]
  resources :seasons,     :only => [:show]

  match 'attachments/:slug(/:style)' => 'attachments#show'

  match 'admin/' => 'admin#index'
  namespace :admin do
    #The resources pages:
    match 'resources/*action' => 'resources', :as => :resources

    #Answer files
    match 'answer/:id/file' => 'answers#get_file', :as => :answer_get_file

    resources :shows do
      resources :feedbacks, :except => [:show]

      collection do
        get 'query_xts'
      end

      member do
        put 'add_questionnaire'
      end
    end

    resources :workshops

    resources :venues
    resources :seasons
    resources :news

    resources :opportunities do
      member do
        put 'approve'
        put 'reject'
      end
    end

    resources :editable_blocks, :except => [:show]

    resources :users do
      member do
        post 'reset_password'
      end
    end

    resources :roles
    get '/permissions/grid' => 'permissions#grid', :as => :permissions
    post '/permissions/grid' => 'permissions#update_grid', :as => :permissions

    resources :techie_families do
      collection do
        get 'graph'
      end
    end

    resources :staffing_templates
    resources :staffings do
      member do
        get 'show_sign_up'
      end

      collection do
        get 'new_for_show'
        put 'create_for_show'
      end
    end

    match '/staffings/job/:id/sign_up_confirm' => 'staffings#sign_up_confirm', :via => :get, :as => :sign_up_confirm
    match '/staffings/job/:id/sign_up' => 'staffings#sign_up', :via => :put, :as => :staffing_sign_up

    match '/proposals' => redirect('/admin/proposals/calls')
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

      match '/about' => 'proposals#about'
      resources :call_question_templates
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

    match '/reports/' => 'reports#index', :as => "reports"
    match '/reports/:action', :controller => 'reports', :as => "report"

    match 'jobs/:action' => 'job_control', :as => "jobs"

    get "/help/:action" => 'help', :as => "help"
  end

  match 'archives(/:start_month/:start_year/:end_month/:end_year)' => 'archives#index', :as => "archives_index"
  match 'archives(/:target)/set_date' => 'archives#set_date', :via => :post
  namespace :archives do
    match 'shows(/:start_month/:start_year/:end_month/:end_year)' => 'shows#index', :as => :shows_index
    match 'proposals(/:start_month/:start_year/:end_month/:end_year)' => 'proposals#index', :as => :proposals_index
  end

  post 'markdown/preview' => 'markdown#preview'

  post 'newsletter/subscribe' => 'newsletter#subscribe', :as => :newsletter_subscribe

  match 'about' => 'about#index', :as => :about_index
  match 'about/*action' => 'about', :as => :about

  match 'getinvolved' => 'get_involved#index', :as => :get_involved_index
  match 'getinvolved/*action' => 'get_involved', :as => :get_involved

  # ERROR PAGES - match to ensure correct response code is sent
  match '/404' => 'static#render_404'
  match '/500' => 'static#render_500'

  match '/:id' => 'seasons#show', :constraints => ExistingSeasonConstraint.new
  match '*action' => 'static', :as => :static

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
