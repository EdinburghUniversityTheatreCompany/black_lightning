require 'silencer'

ChaosRails::Application.routes.draw do
  devise_for :users

  use_doorkeeper
  use_doorkeeper_openid_connect

  root to: 'static#home'

  match '*path', to: 'application#options', via: :options

  # devise_for :users, controllers: { registrations: 'registrations' } do
  #   post 'users/stripe'      , to: 'registrations#create_with_stripe', as: :user_stripe_registration

  #   get  'users/reactivation', to: 'registrations#reactivation', as: :user_reactivation
  #   post 'users/reactivate'  , to: 'registrations#reactivate',   as: :reactivate_user
  #   post 'users/reactivate/stripe', to: 'registrations#reactivate_with_stripe', as: :reactivate_user_stripe
  # end

  resources :shows,       only: [:index, :show]
  resources :workshops,   only: [:index, :show]
  resources :news,        only: [:index, :show]
  resources :venues,      only: [:index, :show]
  resources :seasons,     only: [:index, :show]

  resources :membership_activation_tokens, only: [] do
    member do
      get 'activate', to: 'membership_activation_tokens#activate'
      put 'submit', to: 'membership_activation_tokens#submit'
      patch 'submit', to: 'membership_activation_tokens#submit'
    end
  end

  resources :users, only: [:show] do
    collection do
      get 'current', to: 'users#current'
    end
  end

  get 'marketing_creatives/sign_up', to: 'admin/marketing_creatives/profiles#sign_up'
  # TODO: Corresponding create, maybe?

  # Defined in the silencer initializer.
  COMPLAINTS_ALIASES.each do |path|
    get path, to: redirect('complaints/new')
  end

  resources :complaints, only: [:new, :create]

  get 'events/xts/:id', to: 'events#find_by_xts_id'
  get 'attachments/:slug(/:style)', to: 'attachments#file', as: 'attachment'

  namespace :admin do
    get '', to: 'dashboard#index'

    # The resources pages:_inde
    get 'resources', to: 'resources#page', as: :resources_index
    get 'resources/membership_checker', to: 'resources#membership_checker', as: :resources_membership_checker
    get 'resources/(*page)', to: 'resources#page', as: :resources

    # Answer files
    get 'answer/:id/file', to: 'answers#get_file', as: :answer_get_file

    resources :shows do
      resources :feedbacks, except: [:show]

      collection do
        get 'query_xts'
      end

      member do
        post 'create_staffing_debts', to: 'shows#create_staffing_debts'
        post 'create_maintenance_debts', to: 'shows#create_maintenance_debts'
        get 'xts_report'
        post 'convert_to_season', to: 'shows#convert_to_season'
        post 'convert_to_workshop', to: 'shows#convert_to_workshop'
      end
    end

    resources :workshops

    resources :debt_notifications, only: [:index]

    resources :staffing_debts do
      member do
        put 'assign'
        put 'unassign'
      end
    end

    resources :maintenance_debts do
      member do
        put 'convert_to_staffing_debt'
      end
    end

    resources :debts

    resources :venues
    resources :seasons
    resources :news
    resources :fault_reports

    resources :event_tags
    resources :attachment_tags

    resources :attachments, only: [:index]

    resources :opportunities do
      member do
        put 'approve'
        put 'reject'
      end
    end

    resources :membership, only: [] do
      collection do
        get 'check_membership', to: 'membership#check_membership'
      end
    end

    resources :editable_blocks
    resources :mass_mails

    resources :users do
      member do
        post 'reset_password'
      end

      collection do
        get  'autocomplete_list', constraints: { format: :json }
      end
    end

    # resources :membership_cards, only: [:index, :show, :create, :destroy] do
    #   get 'generate_card'
    # end

    resources :membership_activation_tokens, only: [:new] do
      collection do
        post 'create_activation', to: 'membership_activation_tokens#create_activation'
        post 'create_reactivation', to: 'membership_activation_tokens#create_reactivation'
      end
    end

    resources :roles do
      member do
        post 'add_user', to: 'roles#add_user'
      end
    end

    get  '/permissions/grid', to: 'permissions#grid', as: :permissions
    post '/permissions/grid', to: 'permissions#update_grid', as: :update_permissions

    resources :techies do
      collection do
        get 'tree'
      end
    end

    get 'techie_families', to: 'techies#index'

    namespace :marketing_creatives do
      resources :profiles do
        collection do
          get 'sign_up', to: 'profiles#sign_up'
        end

        member do
          put 'approve'
          put 'reject'
        end
      end

      # Looks a bit weird but necessary to get the url to be admin/marketing_creatives.
      # Needs to be after the other resources or it will try to look for a category with url "profile" for example.
      resources '', controller: 'categories', as: 'categories'
    end

    resources :staffing_templates

    resources :staffings do
      collection do
        get ':slug/grid', to: 'staffings#grid', format: :html, as: :grid
        get 'guidelines'
      end
    end

    match '/staffings/job/:id/sign_up_confirm', to: 'staffings#sign_up_confirm', via: [:get, :put], as: :sign_up_confirm
    put '/staffings/job/:id/sign_up', to: 'staffings#sign_up', as: :staffing_sign_up

    get '/proposals', to: redirect('/admin/proposals/calls')
    namespace :proposals do
      resources :calls do
        member do
          put 'archive'
        end

        resources :proposals, only: :index
      end

      resources :proposals, except: :index do
        member do
          put 'approve'
          put 'reject'
          put 'convert'
        end
      end

      get '/about', to: 'proposals#about'
      resources :call_question_templates
    end

    namespace :questionnaires do
      resources :questionnaires do
        member do
          get  'answer', to: 'questionnaires#answer'
          put 'answer', to: 'questionnaires#set_answers'
          patch 'answer', to: 'questionnaires#set_answers'
        end
      end

      resources :questionnaire_templates
    end

    resources :complaints, except: [:new, :create] do
      get 'new', to: redirect('/complaints/new')
    end

    get '/reports/', to: 'reports#index', as: 'reports'
    namespace 'reports' do
      %w(roles members newsletter_subscribers staffing).each do |action|
        put action, action: action, as: action
      end
    end

    namespace 'jobs' do
      %w(overview working pending failed remove retry).each do |action|
        get action, action: action, as:  action, controller: '/admin/job_control'
      end
    end

    namespace 'help' do
      %w(kramdown venue_location).each do |action|
        get action, action: action, as:  action, controller: '/admin/help'
      end
    end

    get 'committee', to: '/static#committee', as: :static_committee

    # Test route
    if Rails.env.test? || Rails.env.development?
      get 'dashboard/widget/:widget_name', to: 'dashboard#widget'
    end
  end

  get 'archives', to: 'archives#index', as: :archives_index
  namespace :archives do
    get 'shows', to: 'shows#index', as: :shows_index
    get 'workshops', to: 'workshops#index', as: :workshops_index
    get 'proposals', to: 'proposals#index', as: :proposals_index
  end

  post 'markdown/preview', to: 'markdown#preview'

  get 'about', to: 'about#page', as: :about_index
  get 'about/(*page)', to: 'about#page', as: :about

  get 'get_involved', to: 'get_involved#page', as: :get_involved_index
  get 'get_involved/opportunities', to: 'get_involved#opportunities', as: :get_involved_opportunities
  get 'get_involved/(*page)', to: 'get_involved#page', as: :get_involved

  get 'youth', to: redirect('/getinvolved/youth_project')

  # Use bedlamtheatre.co.uk/:slug to find a season
  get '/:id', to: 'seasons#show', constraints: Constraints::ExistingSeason.new

  # Other static pages. The approach using %w(...) does not work without updating all references to static_path.
  get '/*page', to: 'static#show', as: :static, constraints: lambda { |request|
    # Exclude active_storage paths from being redirected to the 404 page.
    !request.path.starts_with?('/rails/active_storage') && !request.path.starts_with?('/assets')
  }

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id', to: 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase', to: 'catalog#purchase', as: :purchase
  # This route can be invoked with purchase_url(:id, to: product.id)

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
  #       get 'recent', :on, to: :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # See how all your routes lay out with "rails routes"
end
