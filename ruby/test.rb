require 'redis'

id = 1
redis = Redis.new(:host=>"127.0.0.1",:port=>6379)
redis.set "keyword-#{id}","foo"
g1 = redis.get "keyword_1"
puts g1
