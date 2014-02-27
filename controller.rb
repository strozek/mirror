require 'logger'
require 'sequel'

module MirrorHelpers

	class C
		@logger = nil
		@db = nil

		# Private methods

		def initialize
			@logger = Logger.new("log/mirror.log", 10, 1024000)
			@logger.datetime_format = "%Y-%m-%d %H:%M:%S "
		  @logger.level = Logger::DEBUG
			@logger.debug("Controller initialized")
			pwd = File.dirname(__FILE__)
			@db = Sequel.connect("sqlite://#{pwd}/db/mirror.db")
		end

		@@instance = nil

	  def hasClosed
	    return (@logger==nil)
	  end
	 
	 	def log
	 		@logger
	 	end

	 	def db
	 		@db
	 	end

	 	def close
			@logger.debug("Controller closed.")
	    @logger.close
	    @logger = nil
			@db.disconnect
	    @db = nil
	  end

	  def self.instance
	    if(@@instance==nil || @@instance.hasClosed)
	      @@instance = C.new
	    end
	    return @@instance
	  end

	  # Public methods

		def self.log
			return instance.log
		end

		def self.db
			return instance.db
		end

		def self.close
			instance.close
		end
	end

end
