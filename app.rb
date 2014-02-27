require 'json'
pwd = File.dirname(__FILE__)
require "#{pwd}/controller"
require "#{pwd}/user"

class Mirror < Sinatra::Base

  include MirrorHelpers
	enable :sessions

	def fail(message)
		result = {:success => false, :message => message}
		halt result.to_json
	end

	# In development, tell shotgun to honor sessions
	if(settings.development?)
		configure do
			set :session_secret, "secret"
		end
	end

	# Ensure the user is logged in, and fetch standard info from params (currently, channel from channelId)
	def requireLoggedInUser(redirectUrl=nil)
		if(session[:userId]==nil)
			if(redirectUrl)
				redirect redirectUrl
			else
				fail("You need to log in first")
			end
		else
			@user = User.new(session[:userId])
		end
	end

	before do
		@result = {:success => true}
	end

	after do
		C.close
	end

	##### Public GET interface

	get '/' do
		requireLoggedInUser '/login'
		erb :index
	end

	get '/a/:id/:password' do
		C.log.info("#{params[:id]} attempting to sign in with quicklogin")
		userId = User::tryGetFromId(params[:id], params[:password])
		if(userId!=nil)
			session[:userId] = userId
			@user = User.new(userId)
			erb :index
		else
			redirect '/'
		end
	end

	get '/' do
		requireLoggedInUser '/login'
		erb :index
	end

	get '/stats' do
		requireLoggedInUser '/login/stats'
		erb :stats
	end

	get '/activity/my' do
		requireLoggedInUser '/login/activity/my'
		@user.updateMyActivityView
		@activity = 'my'
		erb :activity
	end

	get '/activity/team' do
		requireLoggedInUser '/login/activity/team'
		@user.updateTeamActivityView
		@activity = 'team'
		erb :activity
	end

	get '/admin' do
		requireLoggedInUser '/login/admin'
		erb :admin
	end

	get %r{/login([a-z/]*)} do |returnPage|
		erb :login, :locals => {:returnPage => returnPage!='' ? returnPage : '/'}
	end

	get '/logout' do
		session[:userId] = nil
		redirect '/'
	end

	##### Private GET interface

	get '/createadmin/:email' do
		url = User::createAdmin(params[:email], request.host)
		redirect url
	end

	##### API

	get_or_post '/getfeedback' do # :days, :sender, :recipient
		begin
			requireLoggedInUser
			C.log.info("User #{@user.email} fetching feedback")
			@result[:feedback] = @user.getFeedback(params[:days], params[:sender], params[:recipient])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} fetching feedback: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/signin' do # :email, :password
		begin
			C.log.info("#{params[:email]} attempting to sign in")
			userId = User::tryGet(params[:email], params[:password])
			if(userId!=nil)
				C.log.info("User id is #{userId}")
				session[:userId] = userId
			else
				fail("Incorrect email or password")
			end
		rescue Exception=>e
			C.log.warn("Error while #{params[:email]} signing in: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editname' do # :name
		begin
			requireLoggedInUser
			C.log.info("User #{@user.email} editing name to #{params[:name]}")
			@user.editName(params[:name])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} changing name: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editpassword' do # :password
		begin
			requireLoggedInUser
			C.log.info("User #{@user.email} editing password")
			@user.editPassword(params[:password])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} changing password: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editteamname' do # :name
		begin
			requireLoggedInUser
			C.log.info("User #{@user.email} editing team name to #{params[:name]}")
			@user.editTeamName(params[:name])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} changing team name: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editmembers' do # :members
		begin
			requireLoggedInUser
			C.log.info("Admin #{@user.email} editing members to #{params[:members]}")
			@user.editMembers(params[:members])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} editing members: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editbadges' do # :badges
		begin
			requireLoggedInUser
			C.log.info("Admin #{@user.email} editing badges to #{params[:badges]}")
			@user.editBadges(params[:badges])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} editing badges: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/editscope' do # :field, :value
		begin
			requireLoggedInUser
			C.log.info("Admin #{@user.email} changing #{params[:field]} scope to #{params[:value]}")
			@user.editScope(params[:field], params[:value].to_i)
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} changing scope: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/sendemails' do
		begin
			requireLoggedInUser
			C.log.info("Sending emails for team members administered by #{@user.email}")
			@user.sendEmails(request.host)
		rescue Exception=>e
			C.log.warn("Error while sending emails for team members of user #{@user.email}: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

	get_or_post '/send' do # :recipient, :badges, :feedback, :anonymous
		begin
			requireLoggedInUser
			C.log.info("User #{@user.email} providing feedback for #{params[:recipient]}")
			@user.giveFeedback(params[:recipient].to_i, params[:badges], params[:feedback], params[:anonymous])
		rescue Exception=>e
			C.log.warn("Error while #{@user.email} giving feedback: "+e.message)
			fail(e.message)
		end
		@result.to_json
	end

end
