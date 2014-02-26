require 'rubygems'
require 'sequel'

begin
	db = Sequel.connect('sqlite://mirror.db')
	db.create_table(:users) do
		primary_key :id
		String :email
		String :password
		String :name
		TrueClass :passwordChanged
		DateTime :lastMyActivityView
		DateTime :lastTeamActivityView
	end
	db.create_table(:teams) do
		primary_key :id
		String :name
		Integer :adminId
		Integer :senderScope		# 0: no override, 1: override ok
		Integer :recipientScope	# 0: nothing, 1: totals, 3: anonymous, 4: everything
		Integer :everyoneScope	# 0: nothing, 1: team totals, 2: member totals, 3: anonymous, 4: everything
	end
	db.create_table(:teammembers) do
		primary_key :id
		Integer :teamId
		Integer :userId
	end
	db.create_table(:badges) do
		primary_key :id
		Integer :teamId
		String :name
	end
	db.create_table(:feedback) do
		primary_key :id
		Integer :teamId
		Integer :senderId
		Integer :recipientId
		Text :text
		TrueClass :anonymous
		DateTime :timestamp
	end
	db.create_table(:feedbackbadges) do
		primary_key :id
		Integer :feedbackId
		Integer :badgeId
	end
rescue SQLite3::Exception => e 
	puts "Exception occured"
	puts e
ensure
	db.disconnect if db
end
