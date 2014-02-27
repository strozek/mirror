require 'sequel'
require 'mail'
require 'time'

module MirrorHelpers

	class User

		include MirrorHelpers
		
		# Note: every user belongs to exactly 1 team. Only 1 of all of this team's members is an admin
		attr_accessor :id, :email, :name, :passwordChanged
		attr_accessor :teamId, :teamName
		attr_accessor :senderScope, :recipientScope, :everyoneScope
		attr_accessor :membersNotMe, :membersString, :badges, :badgesString
		attr_accessor :myRecentActivityCount, :allRecentActivityCount
		attr_accessor :stats

		# For logging in, return the user ID (if password correct) or nil
		def self.tryGet(email, password)
			user = c.db[:users].where(:email=>email, :password=>password).first
			if(user)
				return user[:id]
			else
				return nil
			end
		end

		# For logging in with quicklogin (first timers), return the user ID or nil
		def self.tryGetFromId(id, password)
			user = c.db[:users].where(:id=>id, :password=>password).first
			if(user)
				return user[:id]
			else
				return nil
			end
		end

		def self.getDisplayName(id)
			user = c.db[:users].where(:id=>id).first
			return user[:name] || user[:email]
		end

		def self.createAdmin(email, host)
			password = generatePassword
			if(c.db[:users].where(:email=>email).count>0)
				raise "User #{email} already exists"
			end
			userId = c.db[:users].insert(:email=>email, :password=>password)
			teamId = c.db[:teams].insert(:adminId => userId, :senderScope=>1, :recipientScope=>4, :everyoneScope=>4)
			c.db[:teammembers].insert(:teamId => teamId, :userId => userId)
			url = "http://#{host}/a/#{userId}/#{password}"
			return url
		end

		def self.generatePassword(size=6)
		  charset = %w{ 2 3 4 6 7 9 A C D E F G H J K M N P Q R T V W X Y Z}
		  (0...size).map{ charset.to_a[rand(charset.size)] }.join
		end

		# For admin adding members, return the user ID (creating the user if necessary)
		def self.getOrCreate(email)
			user = c.db[:users].where(:email=>email).first
			if(user)
				return user[:id]
			else
				id = c.db[:users].insert(:email => email, :password => generatePassword)
				return id
			end
		end

		def initialize(id)
			user = c.db[:users].where(:id => id).first
			@id = id
			@email = user[:email]
			@name = user[:name]
			@passwordChanged = user[:passwordChanged]
			@teamId = c.db[:teammembers].where(:userId => @id).first[:teamId]
			team = c.db[:teams].where(:id => @teamId).first
			if(!team)
				raise "You don't belong to any team"
			end
			@teamName = team[:name]
			@senderScope = team[:senderScope]
			@recipientScope = team[:recipientScope]
			@everyoneScope = team[:everyoneScope]
			currentMembers = c.db[:teammembers].where(:teamId => @teamId).map(:userId)
			emails = []
			@membersNotMe = []
			currentMembers.each { |memberId|
				member = c.db[:users].where(:id=>memberId).first
				if(memberId != @id)
					emails.push(member[:email])
					@membersNotMe.push({:id=>memberId, :name=>(member[:name] || member[:email])})
				end
			}
			@membersString = emails.join(', ')
			@badges = []
			currentBadges = c.db[:badges].where(:teamId => @teamId)
			currentBadges.each { |badge|
				@badges.push({:id=>badge[:id], :name=>badge[:name]})
			}
			@badgesString = currentBadges.map(:name).join(', ')
			@myRecentActivityCount = (@recipientScope>=3) ? c.db[:feedback]
				.where(:teamId => @teamId, :recipientId => @id)
				.where{timestamp > (user[:lastMyActivityView] || 0)}.count : 0
			@allRecentActivityCount = (@everyoneScope>=3) ? c.db[:feedback]
				.where(:teamId => @teamId)
				.where(Sequel.~(:senderId => @id))
				.where{timestamp > (user[:lastTeamActivityView] || 0)}.count : 0

			dataset = c.db[:feedback].where(:teamId=>@teamId).where{timestamp>Time.now-30*60*60*24}
			@stats = {
				:iReceived => @recipientScope>=1 ? dataset.where(:recipientId=>@id).count : nil,
				:teamReceivedAndSent => @everyoneScope>=1 ? (dataset.count*1.0/currentMembers.count).round(1) : nil,
				:iReceivedByMember => @recipientScope>=1 ? getReceivedByMemberStats(dataset) : nil,
				:teamReceivedByMember => @everyoneScope>=2 ? getTeamReceivedByMemberStats(dataset) : nil,
				:badgesIReceived => @recipientScope>=1 ? getBadgesIReceivedStats(dataset) : nil,
				:badgesTeamReceivedAndSent => @everyoneScope>=1 ? getBadgesTeamReceivedStats(dataset) : nil,
				:iSent => dataset.where(:senderId=>@id).count,
				:iSentByMember => getSentByMemberStats(dataset),
				:teamSentByMember => @everyoneScope>=2 ? getTeamSentByMemberStats(dataset) : nil,
				:badgesIAwarded => getBadgesIAwardedStats(dataset)
			}
			c.log.info("Fetched user with id #{id} and email #{@email}")
		end

		def getReceivedByMemberStats(dataset)
			result = []
			@membersNotMe.each { |member|
				count = dataset.where(:senderId=>member[:id], :recipientId=>@id, :anonymous=>'false').count
				if(count>0)
					result.push({:name=>member[:name], :count=>count})
				end
			}
			anonymousCount = dataset.where(:recipientId=>@id, :anonymous=>'true').count
			if(anonymousCount>0)
				result.push({:name=>'<span class="text text-muted">anonymous</span>', :count=>anonymousCount})
			end
			result
		end

		def getTeamReceivedByMemberStats(dataset)
			result = []
			memberCount = c.db[:teammembers].where(:teamId => @teamId).count
			@membersNotMe.each { |member|
				count = dataset.where(:senderId=>member[:id], :anonymous=>'false').count
				if(count>0)
					result.push({:name=>member[:name], :count=>(count*1.0/memberCount).round(1)})
				end
			}
			anonymousCount = dataset.where(:anonymous=>'true').count
			if(anonymousCount>0)
				result.push({:name=>'<span class="text text-muted">anonymous</span>', :count=>(anonymousCount*1.0/memberCount).round(1)})
			end
			result
		end

		def getBadgesIReceivedStats(dataset)
			result = []
			@badges.each { |badge|
				count = dataset.where(:recipientId=>@id).join(:feedbackbadges, :feedbackId=>:id).where(:badgeId=>badge[:id]).count
				if(count>0)
					result.push({:name=>badge[:name], :count=>count})
				end
			}
			result
		end

		def getBadgesTeamReceivedStats(dataset)
			result = []
			memberCount = c.db[:teammembers].where(:teamId => @teamId).count
			@badges.each { |badge|
				count = dataset.join(:feedbackbadges, :feedbackId=>:id).where(:badgeId=>badge[:id]).count
				if(count>0)
					result.push({:name=>badge[:name], :count=>(count*1.0/memberCount).round(1)})
				end
			}
			result
		end

		def getSentByMemberStats(dataset)
			result = []
			@membersNotMe.each { |member|
				count = dataset.where(:senderId=>@id, :recipientId=>member[:id]).count
				if(count>0)
					result.push({:name=>member[:name], :count=>count})
				end
			}
			result
		end

		def getTeamSentByMemberStats(dataset)
			result = []
			memberCount = c.db[:teammembers].where(:teamId => @teamId).count
			@membersNotMe.each { |member|
				count = dataset.where(:recipientId=>member[:id]).count
				if(count>0)
					result.push({:name=>member[:name], :count=>(count*1.0/memberCount).round(1)})
				end
			}
			result
		end

		def getBadgesIAwardedStats(dataset)
			result = []
			@badges.each { |badge|
				count = dataset.where(:senderId=>@id).join(:feedbackbadges, :feedbackId=>:id).where(:badgeId=>badge[:id]).count
				if(count>0)
					result.push({:name=>badge[:name], :count=>count})
				end
			}
			result
		end

		def last30DaysGraph
			if(@recipientScope<3)
				return ''
			end
			html = ''
			html += '<tr class="active"><th></th>'
			for i in -29..0
				dayOfWeek = (Time.now+i*24*60*60).strftime("%u").to_i
				date = (Time.now+i*24*60*60).strftime("%-m/%d")
				if(i==-29)
					html += "<td colspan=" + (8-dayOfWeek).to_s + ">" + date + "</td>"
				elsif(dayOfWeek==1)
					html += "<td colspan=" + (i>=-6 ? (-i+1) : 7).to_s + ">" + date + "</td>"
				end
			end
			html += '</tr>'
			@badges.each { |badge|
				html += '<tr><th class="rightAlign active"><span class="label label-default">' + badge[:name] + '</span></th>';
				for i in -29..0
					dateFrom = Time.parse((Time.now+i*24*60*60).strftime("%Y-%m-%d"))
					dateTo = dateFrom+24*60*60
					count = c.db[:feedback]
						.where(:teamId=>@teamId, :recipientId=>@id)
						.where{timestamp >= dateFrom}
						.where{timestamp < dateTo}
						.join(:feedbackbadges, :feedbackId=>:id)
						.where(:badgeId=>badge[:id])
						.count
					html += '<td><span class="badge">' + (count>0 ? count.to_s : '') + '</span></td>'
				end
				html += '</tr>'
			}
			html
		end

		def owner?
			return (c.db[:teams].where(:id => @teamId).first[:adminId] == @id)
		end

		def sanitize(name)
			return name.gsub(/"/, "'").gsub(/\s+/," ")
		end

		def feedbackItemVisible?(row)
			if(row[:senderId]==@id)
				return true
			end
			if(row[:recipientId]==@id)
				return(@recipientScope>=3)
			end
			return(@everyoneScope>=3)
		end

		def feedbackItemAnonymous?(row)
			if(row[:senderId]==@id)
				return false
			end
			if(row[:recipientId]==@id)
				return row[:anonymous]
			end
			return(@everyoneScope==3)
		end

		def getFeedback(daysString, senderString, recipientString)
			feedback = []

			fromDate = (daysString=='all') ? 0 : Time.now-daysString.to_i*60*60*24
			dataset = c.db[:feedback].where(:teamId => @teamId).where{timestamp > fromDate}

			if(senderString!='all' && senderString!='allbutme' && senderString!='anonymous')
				dataset = dataset.where(:senderId => senderString.to_i)
			end

			if(recipientString!='all')
				dataset = dataset.where(:recipientId => recipientString.to_i)
			end

			dataset.order(Sequel.desc(:timestamp)).each { |row|
				if(	feedbackItemVisible?(row) && 
						(senderString!='anonymous' || feedbackItemAnonymous?(row)) &&
						(senderString!='allbutme' || row[:senderId]!=@id))
					badges = []
					c.db[:feedbackbadges].where(:feedbackId=>row[:id]).each { |badgeRow|
						badgeName = c.db[:badges].where(:id=>badgeRow[:badgeId]).first[:name]
						badges.push(badgeName)
					}
					startOfYear = Time.parse(Time.now.year.to_s+'-1-1')
					if(row[:timestamp]>=startOfYear)
						timestamp = row[:timestamp].strftime("%b %-d %l:%M%P")
					else
						timestamp = row[:timestamp].strftime("%b %-d %Y")
					end
					if(feedbackItemAnonymous?(row))
						sender = '<span class="text text-muted">anonymous</span>'
					else
						sender = User::getDisplayName(row[:senderId])
					end
					if(row[:senderId]==@id)
						sender = '<span class="text text-primary">me</span>'
					end
					if(row[:recipientId]==@id)
						recipient = '<span class="text text-primary">me</span>'
					else
						recipient = User::getDisplayName(row[:recipientId])
					end
					item = {
						:timestamp=>timestamp,
						:sender=>sender,
						:recipient=>recipient,
						:badges=>badges,
						:text=>row[:text]
					}
					feedback.push(item)
				end
			}
			return feedback
		end

		def updateMyActivityView
			c.db[:users].where(:id => @id).update(:lastMyActivityView => Time.now)
		end

		def updateTeamActivityView
			c.db[:users].where(:id => @id).update(:lastTeamActivityView => Time.now)
		end

		def editName(name)
			@name = sanitize(name)
			c.db[:users].where(:id => @id).update(:name => name)
			c.log.info("Changed user name for user #{@email} to #{name}")
		end

		def editPassword(password)
			c.db[:users].where(:id => @id).update(:password => password, :passwordChanged => true)
			c.log.info("Changed password for user #{@email}")
		end

		def editTeamName(name)
			raise "You don't administer this team" if(!owner?)
			@teamName = sanitize(name)
			c.db[:teams].where(:id=>@teamId).update(:name=>@teamName)
			c.log.info("Changed team name for user #{@email} to #{name}")
		end

		def editMembers(membersString)
			raise "You don't administer this team" if(!owner?)
			members = sanitize(membersString).split(/\s*,\s*/)
			# Ensure each member specified is or becomes a part of the team
			members.each { |member|
				id = User::getOrCreate(member)
				if(c.db[:teammembers].where(:teamId => @teamId, :userId => id).count==0)
					c.db[:teammembers].insert(:teamId => @teamId, :userId => id)
				end
			}
			# Ensure we don't have extra members
			currentMembers = c.db[:teammembers].where(:teamId => @teamId).map(:userId)
			currentMembers.each { |memberId|
				email = c.db[:users].where(:id=>memberId).first[:email]
				if(!members.include?(email) && memberId!=@id)
					c.db[:teammembers].where(:teamId => @teamId, :userId => memberId).delete
				end
			}
			c.log.info("Changed membership of user #{@email} team's to #{membersString}")
		end

		def editBadges(badgesString)
			raise "You don't administer this team" if(!owner?)
			badges = sanitize(badgesString).split(/\s*,\s*/)
			# Ensure each badge specified is or becomes an entry
			badges.each { |badge|
				if(c.db[:badges].where(:teamId => @teamId, :name => badge).count==0)
					c.db[:badges].insert(:teamId => @teamId, :name => badge)
				end
			}
			# Ensure we don't have extra badges
			currentBadges = c.db[:badges].where(:teamId => @teamId).map(:name)
			currentBadges.each { |badge|
				if(!badges.include?(badge))
					c.db[:badges].where(:teamId => @teamId, :name => badge).delete
				end
			}
			c.log.info("Changed badges of user #{@email} team's to #{badgesString}")
		end

		def editScope(label, value)
			raise "You don't administer this team" if(!owner?)
			if(label=='sender')
				c.db[:teams].where(:id => @teamId).update(:senderScope => value)
			elsif(label=='recipient')
				c.db[:teams].where(:id => @teamId).update(:recipientScope => value)
			elsif(label=='everyone')
				c.db[:teams].where(:id => @teamId).update(:everyoneScope => value)
			else
				raise "Unknown label #{label}"
			end
			c.log.info("Changed #{label} scope to #{value}")
		end

		def sendEmails(host)
			raise "You don't administer this team" if(!owner?)
			currentMembers = c.db[:teammembers].where(:teamId => @teamId).map(:userId)
			currentMembers.each { |memberId|
				user = c.db[:users].where(:id=>memberId).first
				email = user[:email]
				password = user[:password]
				url = "http://#{host}/a/#{memberId}/#{password}"
				# TODO: For demos
				if(memberId != @id && (email =~ /test\.com/)==nil)
					mail = Mail.new do
						from "mirror <no-reply@#{host}>"
						to email
						subject 'You have been invited to be part of Mirror'
						text_part do
			 				body 	"You can log in to Mirror by going to the following URL\n"+
			 		 					"\n"+
			 		 					url+
			 		 					"\n"+
			 		 					"The mirror team"
						end
						html_part do
			  			content_type 'text/html; charset=UTF-8'
			  			body "You can log in to Mirror by following this link: <a href='#{url}'>#{url}</a>.<br><br><i>The mirror team</i>"
			  		end
					end
					mail.deliver!
				end
			}
		end

		def giveFeedback(recipientId, badgesString, feedbackText, anonymous)
			feedbackId = c.db[:feedback].insert(
				:teamId => @teamId,
				:senderId => @id,
				:recipientId => recipientId,
				:text => feedbackText,
				:timestamp => Time.now,
				:anonymous => (@senderScope==1) ? anonymous : (@recipientScope==3))
			badgesString.split(/,/).each { |badge|
				c.db[:feedbackbadges].insert(:feedbackId => feedbackId, :badgeId => badge)
			}
		end

	end

end
