class AuthenticationsController < ApplicationController
  before_action :check_state!, only: [:callback]

  def login
    redirect_to root_path, flash: { success: 'Already logged in!' } if signed_in?
    redirect_to auth_url
  end

  def callback
    # Retrieve access token
    error_redirect! unless (access_token = token_request!(params[:code]))

    # Create user
    rate_limit_redirect! unless (user = GithubService.create_or_update_user(access_token))

    # Log in the user
    log_in!(user)

    # Add repositories and redirect to profile
    if GithubService.load_repositories(access_token)
      profile_redirect! 
    else
      rate_limit_redirect!
    end
  end

  def logout
    log_out!
    redirect_to root_path, flash: { notice: 'Logged out!' }
  end

  def login_rate_limited; end

  private

  def auth_url
    "https://github.com/login/oauth/authorize?client_id=#{ENV['GITHUB_CLIENT_ID']}&" + 
    "#{{ redirect_uri: ENV['GITHUB_CALLBACK_URL'] }.to_query}&#{{ scope: 'repo' }.to_query}&state=#{state}"
  end

  def check_state!
    redirect_to root_path, flash: { error: 'An error occurred; please try again' } unless params[:state] == state
  end

  def log_in!(user)
    session[:user_id] = user.id
  end

  def log_out!
    session.delete(:user_id)
  end

  def error_redirect!
    redirect_to root_path, flash: { error: 'An error occurred; please try again' }
  end

  def rate_limit_redirect!
    redirect_to login_rate_limited_path
  end

  def profile_redirect!
    redirect_to profile_path, flash: { success: 'Logged in!' }
  end

  def state
    if session[:state]
      cur_state = session[:state]
      session.delete(:state)
      cur_state
    else
      state = SecureRandom.hex
      session[:state] = state
      state
    end
  end

  def token_request!(code)
    # Initialize HTTP library
    url = URI.parse('https://github.com')
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    # Create the new request
    request = Net::HTTP::Post.new('/login/oauth/access_token')

    # Set params
    req_params = {}
    req_params[:client_id] = ENV['GITHUB_CLIENT_ID']
    req_params[:client_secret] = ENV['GITHUB_CLIENT_SECRET']
    req_params[:code] = code

    # Add params to request
    request.set_form_data(req_params)

    # Accept JSON
    request['accept'] = 'application/json'

    # Make request and return parsed result
    begin
      response = http.request(request)
    rescue
      nil
    else
      JSON.parse(response.body)['access_token']
    end
  end
end
