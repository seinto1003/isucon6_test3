require 'digest/sha1'

salt = "UTvwauofalYSxUKHMsXk"
password = "684919f714f53ec84aebb87c13bcf41523ff513e"
puts Digest::SHA1.hexdigest(salt + password)
