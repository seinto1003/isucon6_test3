require 'digest/sha1'
require 'json'
require 'net/http'
require 'uri'

require 'erubis'
require 'mysql2'
require 'mysql2-cs-bind'
require 'rack/utils'
require 'sinatra/base'
require 'tilt/erubis'
# add redis
require 'redis'

mysql = Mysql2::Client.new(
  username: 'isucon',
  password: 'isucon',
  database: 'isuda',
  encoding: 'utf8mb4',
  init_command: %|SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'|,
)
puts "mysql"

redis = Redis.new(:host=>"127.0.0.1",:port=>6379)
entries = mysql.xquery(%|
        SELECT * FROM entry
        ORDER BY id  
|)
entries.each do |entry|
   content = entry["description"]
   if redis.exists "content#{entry["id"]}" then
       result = redis.get "content#{entry["id"]}"
       puts entry["id"].to_s + "ok"
   else
        if redis.exists "patern" then
           pattern = redis.get "patern"
        else 
           keywords = mysql.xquery(%| select keyword from entry order by character_length(keyword) desc |)
           pattern = keywords.map {|k| Regexp.escape(k["keyword"]) }.join('|')
           redis.set "patern", pattern
        end
        kw2hash = {}
        hashed_content = content.gsub(/(#{pattern})/) {|m|
          matched_keyword = $1
          if redis.exists "hash#{matched_keyword}" then
              hash = redis.get "hash#{matched_keyword}"
          else 
              redis.set "hash#{matched_keyword}", "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}"
              hash = redis.get "hash#{matched_keyword}"
          end
          kw2hash[matched_keyword] = hash
#          "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}".tap do |hash|
#            kw2hash[matched_keyword] = hash
#          end
        }
        escaped_content = Rack::Utils.escape_html(hashed_content)
        kw2hash.each do |(keyword, hash)|
            if redis.exists "url#{keyword}"
               keyword_url = redis.get "url#{keyword}"
            else 
               keyword_url =URI("http://172.28.128.3" + "/keyword/#{Rack::Utils.escape_path(keyword)}")
               redis.set "url#{keyword}",keyword_url
            end 
            if redis .exists "anchor#{keyword}"
               anchor = redis.get "anchor#{keyword}" 
            else
                anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
                redis.set "anchor#{keyword}",anchor
            end
            escaped_content.gsub!(hash, anchor)

#          keyword_url = URI("172.28.128.3" + "/keyword/#{Rack::Utils.escape_path(keyword)}")
#          anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
#          puts keyword_url
#          puts anchor
#          escaped_content.gsub!(hash, anchor)
        end
        cos = escaped_content.gsub(/\n/, "<br />\n")
      redis.set "content#{entry["id"]}", cos 
      puts entry["id"].to_s + "ok"
   end
end
