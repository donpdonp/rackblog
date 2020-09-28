module Rackblog
  class Auth
    def initialize(db)
      @token = db
  	end

  	def id_for_token(token)
  		@tokens[token] ||= id_get(token)
  	end

  	def id_get(token)
  		profile = JSON.parse(HTTParty.get(Rackblog.Config.indieauth))
  		puts profile
  	end
  end
end
