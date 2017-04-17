ChaosRails::Application.routes.draw do

  match '*path' => 'application#options', via: :options

  get 'seasons/show'

  devise_for :users, controllers: { registrations: 'registrations' } do
    post 'users/stripe'       => 'registrations#create_with_stripe', as: :user_stripe_registration

    get  'users/reactivation' => 'registrations#reactivation', as: :user_reactivation
    post 'users/reactivate'   => 'registrations#reactivate',   as: :reactivate_user
    post 'users/reactivate/stripe' => 'registrations#reactivate_with_stripe', as: :reactivate_user_stripe
  end

  resources :shows,       only: [:index, :show]
  resources :workshops,   only: [:index, :show]
  resources :news,        only: [:index, :show]
  resources :venues,      only: [:index, :show]
  resources :seasons,     only: [:show]
  resources :users,       only: [:show] do
    collection do
      get 'current'          => 'users#current'
      get 'check_membership' => 'users#check_membership'
    end
  end

  get 'events/xts/:id' => 'events#find_by_xts_id'
  get 'attachments/:slug(/:style)' => 'attachments#show'

  get 'admin/' => 'admin#index'
  namespace :admin do
    # The resources pages:
    get 'resources/*page' => 'resources#page', as: :resources

    # Answer files
    get 'answer/:id/file' => 'answers#get_file', :as => :answer_get_file

    resources :shows do
      resources :feedbacks, except: [:show]

      collection do
        get 'query_xts'
      end

      member do
        put 'add_questionnaire'
        put 'add_maintenance_due'
        put 'add_staffing_due'
        put 'create_sdebts'
        get 'create_mdebts'
        get 'xts_report'
      end
    end

    resources :workshops

    resources :staffing_debts do
      member do
        get 'assign'
        get 'unassign'
      end
    end

    resources :maintenance_debts do
      member do
        put 'convert_to_staffing_debt'
      end
    end

    resources :show_maintenance_debts
    resources :show_staffing_debts


    resources :venues
    resources :seasons
    resources :news
    resources :fault_reports

    resources :opportunities do
      member do
        put 'approve'
        put 'reject'
      end
    end

    resources :editable_blocks, except: [:show]
    resources :mass_mails

    resources :users do
      member do
        post 'reset_password'
      end

      collection do
        get  'autocomplete_list', constraints: { format: :json }
      end
    end

    resources :membership_cards, only: [:index, :show, :create, :destroy] do
      get 'generate_card'
    end

    resources :roles
    get  '/permissions/grid' => 'permissions#grid', :as => :permissions
    post '/permissions/grid' => 'permissions#update_grid', :as => :update_permissions

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
        get ':show_title/grid' => 'staffings#grid', :format => :html, :as => :grid
        get 'guidelines'
      end
    end

    match '/staffings/job/:id/sign_up_confirm' => 'staffings#sign_up_confirm', :via => [:get, :put], :as => :sign_up_confirm
    put '/staffings/job/:id/sign_up' => 'staffings#sign_up', :as => :staffing_sign_up

    get '/proposals' => redirect('/admin/proposals/calls')
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

      get '/about' => 'proposals#about'
      resources :call_question_templates
    end

    namespace :questionnaires do
      resources :questionnaires, except: [:new, :create] do
        member do
          get  'answer' => 'questionnaires#answer'
          post 'answer' => 'questionnaires#set_answers'
        end
      end

      resources :questionnaire_templates
    end

    get '/reports/' => 'reports#index', :as => 'reports'
    get '/reports/:action', controller: 'reports', as: 'report'

    get 'jobs/:action' => 'job_control', :as => 'jobs'

    get '/help/:action' => 'help', :as => 'help'
  end

  get 'archives' => 'archives#index', :as => :archives_index
  namespace :archives do
    get 'shows' => 'shows#index', :as => :shows_index
    get 'workshops' => 'workshops#index', :as => :workshops_index
    get 'proposals' => 'proposals#index', :as => :proposals_index
  end

  post 'markdown/preview' => 'markdown#preview'

  get 'about' => 'about#index', :as => :about_index
  get 'about/*page' => 'about#page', :as => :about

  get 'getinvolved' => 'get_involved#index', :as => :get_involved_index
  get 'getinvolved/opportunities' => 'get_involved#opportunities'
  get 'getinvolved/*page' => 'get_involved#page', :as => :get_involved
  get 'youth', to: redirect('/getinvolved/youth_project')

  # ERROR PAGES - match to ensure correct response code is sent
  get '/404' => 'static#render_404'
  get '/500' => 'static#render_500'

  get '/:id' => 'seasons#show', :constraints => ExistingSeasonConstraint.new
  get '*action' => 'static', :as => :static

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
  root to: 'static#home'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
