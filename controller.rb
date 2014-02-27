require 'logger'
require 'sequel'

module MirrorHelpers

	class Controller
		@logger = nil
		@db = nil

		def initialize
			@logger = Logger.new("log/mirror.log", 10, 1024000)
			@logger.datetime_format = "%Y-%m-%d %H:%M:%S "
		  @logger.level = Logger::DEBUG
			@logger.debug("Controller initialized")
			pwd = File.dirname(__FILE__)
			@db = Sequel.connect("sqlite://#{pwd}/db/mirror.db")
		end

		@@instance = nil
	 
	  def self.instance
	    if(@@instance==nil || @@instance.hasClosed)
	      @@instance = Controller.new
	    end
	    return @@instance
	  end

		def log
			return @logger
		end

		def db
			return @db
		end

	  def hasClosed
	    return (@logger==nil)
	  end

		def close
			@logger.debug("Controller closed.")
	    @logger.close
	    @logger = nil
			@db.disconnect
	    @db = nil
		end
	end

	def c
		Controller.instance
	end

end
