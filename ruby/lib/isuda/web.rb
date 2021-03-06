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
require 'hiredis'
require 'rack-lineprof'

# redisコネクション作

module Isuda
  class Web < ::Sinatra::Base
    use Rack::Lineprof
    enable :protection
    enable :sessions

    set :erb, escape_html: true
    set :public_folder, File.expand_path('../../../../public', __FILE__)
    set :db_user, ENV['ISUDA_DB_USER'] || 'root'
    set :db_password, ENV['ISUDA_DB_PASSWORD'] || ''
    set :dsn, ENV['ISUDA_DSN'] || 'dbi:mysql:db=isuda'
    set :session_secret, 'tonymoris'
    set :isupam_origin, ENV['ISUPAM_ORIGIN'] || 'http://localhost:5050'
    set :isutar_origin, ENV['ISUTAR_ORIGIN'] || 'http://localhost:5000'

# isutrar_setting add
    set :db_user1, ENV['ISUTAR_DB_USER'] || 'root'
    set :db_password1, ENV['ISUTAR_DB_PASSWORD'] || ''
    set :dsn1, ENV['ISUTAR_DSN'] || 'dbi:mysql:db1=isutar'
    set :isuda_origin, ENV['ISUDA_ORIGIN'] || 'http://localhost:5000'

    configure :development do
      require 'sinatra/reloader'

      register Sinatra::Reloader
    end

    set(:set_name) do |value|
      condition {
        user_id = session[:user_id]
        if user_id
          user = db.xquery(%| select name from user where id = ? |, user_id).first
          @user_id = user_id
          @user_name = user[:name]
          halt(403) unless @user_name
        end
      }
    end

    set(:authenticate) do |value|
      condition {
        halt(403) unless @user_id
      }
    end

    helpers do
      def db
        Thread.current[:db] ||=
          begin
            _, _, attrs_part = settings.dsn.split(':', 3)
            attrs = Hash[attrs_part.split(';').map {|part| part.split('=', 2) }]
            mysql = Mysql2::Client.new(
              username: settings.db_user,
              password: settings.db_password,
              database: attrs['db'],
              encoding: 'utf8mb4',
              init_command: %|SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'|,
            )
            mysql.query_options.update(symbolize_keys: true)
            mysql
          end
      end

## isutar db setting
      def db1
        Thread.current[:db1] ||=
          begin
            _, _, attrs_part1 = settings.dsn1.split(':', 3)
            attrs1 = Hash[attrs_part1.split(';').map {|part| part.split('=', 2) }]
            mysql1 = Mysql2::Client.new(
              username: settings.db_user1,
              password: settings.db_password1,
              database: attrs1['db1'],
              encoding: 'utf8mb4',
              init_command: %|SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'|,
            )
            mysql1.query_options.update(symbolize_keys: true)
            mysql1
          end
      end

      def register(name, pw)
        chars = [*'A'..'~']
        salt = 1.upto(20).map { chars.sample }.join('')
        salted_password = encode_with_salt(password: pw, salt: salt)
        db.xquery(%|
          INSERT INTO user (name, salt, password, created_at)
          VALUES (?, ?, ?, NOW())
        |, name, salt, salted_password)
        db.last_id
      end

      def encode_with_salt(password: , salt: )
        Digest::SHA1.hexdigest(salt + password)
      end

      def is_spam_content(content)
        isupam_uri = URI(settings.isupam_origin)
        res = Net::HTTP.post_form(isupam_uri, 'content' => content)
        validation = JSON.parse(res.body)
        validation['valid']
        ! validation['valid']
      end

      def htmlify(content)
        redis = Redis.new(:host=>"127.0.0.1",:port=>6379, :driver => :hiredis)
        if redis.exists "patern" then
           pattern = redis.get "patern"
        else 
           keywords = db.xquery(%| select keyword from entry order by character_length(keyword) desc |)
           pattern = keywords.map {|k| Regexp.escape(k[:keyword]) }.join('|')
           redis.set "patern", pattern
        end
#        kw2hash = {}
#        escaped_content = Rack::Utils.escape_html(content)
        hashed_content = content.gsub(/(#{pattern})/) {|m|
          matched_keyword = $1
          if redis.exists "hash#{matched_keyword}" then
              hash = redis.get "hash#{matched_keyword}"
          else 
              redis.set "hash#{matched_keyword}", "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}"
              hash = redis.get "hash#{matched_keyword}"
          end
          if redis.exists "url#{matched_keyword}"
             keyword_url = redis.get "url#{matched_keyword}"
          else 
             keyword_url =url("/keyword/#{Rack::Utils.escape_path(matched_keyword)}")
             redis.set "url#{matched_keyword}",keyword_url
          end 
          if redis .exists "anchor#{matched_keyword}"
             anchor = redis.get "anchor#{matched_keyword}" 
          else
             anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(matched_keyword)]
             redis.set "anchor#{matched_keyword}",anchor
          end
          anchor
#          kw2hash[matched_keyword] = hash
#          "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}".tap do |hash|
#            kw2hash[matched_keyword] = hash
#          end
        }
#        escaped_content = Rack::Utils.escape_html(hashed_content)
#        kw2hash.each do |(keyword, hash)|
#            if redis.exists "url#{keyword}"
#               keyword_url = redis.get "url#{keyword}"
#            else 
#               keyword_url =url("/keyword/#{Rack::Utils.escape_path(keyword)}")
#               redis.set "url#{keyword}",keyword_url
#            end 
#            if redis .exists "anchor#{keyword}"
#               anchor = redis.get "anchor#{keyword}" 
#            else
#                anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
#                redis.set "anchor#{keyword}",anchor
#            end
#            escaped_content.gsub!(hash, anchor)

#          keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
#          anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
#          escaped_content.gsub!(hash, anchor)
#        end
         hashed_content.gsub(/\n/, "<br />\n")
#        escaped_content.gsub(/\n/, "<br />\n")
      end

      def uri_escape(str)
        Rack::Utils.escape_path(str)
      end

      def load_stars(keyword)
          stars = db1.xquery(%| select * from star where keyword = ? |,keyword).to_a
          body = JSON.generate(stars: stars)
          stars_res = JSON.parse(body)
          stars_res['stars']
      end

# isutarstar
#      def load_stars(keyword)
#        isutar_url = URI(settings.isutar_origin)
#        isutar_url.path = '/stars'
#        isutar_url.query = URI.encode_www_form(keyword: keyword)
#        body = Net::HTTP.get(isutar_url)
#        stars_res = JSON.parse(body)
#        stars_res['stars']
#      end

      def redirect_found(path)
        redirect(path, 302)
      end
    end

    get '/initialize' do
      db.xquery(%| DELETE FROM entry WHERE id > 7101 |)
      db1.xquery('TRUNCATE star')
#      isutar_initialize_url = URI(settings.isutar_origin)
#      isutar_initialize_url.path = '/initialize'
#      Net::HTTP.get_response(isutar_initialize_url)

      content_type :json
      JSON.generate(result: 'ok')
      # redis initialize add
    end

#    get '/setcache' do
#      redis = Redis.new(:host=>"127.0.0.1",:port=>6379)
#      entries = db.xquery(%|
#        SELECT * FROM entry
#        ORDER BY id DESC
#      |)
#      entries.each do |entry|
#        if redis.exists "content#{entry[:id]}" then
#           entry[:html] = redis.get "content#{entry[:id]}"
#        else 
#          redis.set "content#{entry[:id]}", htmlify(entry[:description])
#          entry[:html] = redis.get  "content#{entry[:id]}"
#        end
#      end
#      redirect_found '/'
#    end

    get '/', set_name: true do
      redis = Redis.new(:host=>"127.0.0.1",:port=>6379, :driver => :hiredis)
      per_page = 10
      page = (params[:page] || 1).to_i

      entries = db.xquery(%|
        SELECT * FROM entry
        ORDER BY updated_at DESC
        LIMIT #{per_page}
        OFFSET #{per_page * (page - 1)}
      |)
      entries.each do |entry|
        if redis.exists "content#{entry[:id]}" then
           entry[:html] = redis.get "content#{entry[:id]}"
        else 
          redis.set "content#{entry[:id]}", htmlify(entry[:description])
          entry[:html] = redis.get  "content#{entry[:id]}"
        end
#       entry[:html] = htmlify(entry[:description])

#      if redis.exists entry[:description] then
#         entry[:html] = redis.get entry[:description]
#      else 
#          redis.set entry[:description], htmlify(entry[:description])
#          entry[:html] = redis.get entry[:description] 
#      end
#        entry[:html] = htmlify(entry[:description])

        entry[:stars] = load_stars(entry[:keyword])
      end
      
      if redis.exists "count" then
        total_entries = redis.get "count"
      else 
        total_entries = db.xquery(%| SELECT count(*) AS total_entries FROM entry |).first[:total_entries].to_i
        redis.set "count", total_entries
      end

      last_page = (total_entries.to_f / per_page.to_f).ceil
      from = [1, page - 5].max
      to = [last_page, page + 5].min
      pages = [*from..to]

      locals = {
        entries: entries,
        page: page,
        pages: pages,
        last_page: last_page,
      }
      erb :index, locals: locals
    end

    get '/robots.txt' do
      halt(404)
    end

    get '/register', set_name: true do
      erb :register
    end

    post '/register' do
      name = params[:name] || ''
      pw   = params[:password] || ''
      halt(400) if (name == '') || (pw == '')

      user_id = register(name, pw)
      session[:user_id] = user_id

      redirect_found '/'
    end

    get '/login', set_name: true do
      locals = {
        action: 'login',
      }
      erb :authenticate, locals: locals
    end

    post '/login' do
      name = params[:name]
      user = db.xquery(%| select * from user where name = ? |, name).first
      halt(403) unless user
      halt(403) unless user[:password] == encode_with_salt(password: params[:password], salt: user[:salt])

      session[:user_id] = user[:id]

      redirect_found '/'
    end

    get '/logout' do
      session[:user_id] = nil
      redirect_found '/'
    end

    post '/keyword', set_name: true, authenticate: true do
      redis = Redis.new(:host=>"127.0.0.1",:port=>6379,:driver => :hiredis)
      keyword = params[:keyword] || ''
      halt(400) if keyword == ''
      description = params[:description]
      halt(400) if is_spam_content(description) || is_spam_content(keyword)

      bound = [@user_id, keyword, description] * 2
      db.xquery(%|
        INSERT INTO entry (author_id, keyword, description, created_at, updated_at)
        VALUES (?, ?, ?, NOW(), NOW())
        ON DUPLICATE KEY UPDATE
        author_id = ?, keyword = ?, description = ?, updated_at = NOW()
      |, *bound)
      

      entry = db.xquery(%| select id from entry where keyword = ?|,params[:keyword]).first
      ## redis cache add 2
      if redis.exists "content#{entry[:id]}" then
         redis.del "content#{entry[:id]}"
      end      

      redis.set "hash#{keyword}", "isuda_#{Digest::SHA1.hexdigest(keyword)}"
      keyword_escape = Regexp.escape(keyword)
      keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
      anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
      redis.set "url#{keyword}",keyword_url
      redis.set "anchor#{keyword}",anchor
      redis.set keyword , keyword_escape
      redis.set  "content#{entry[:id]}", htmlify(params[:description])
      if redis.exists "patern" then
         p = redis.get "patern"
         patern_new = p + "|" + keyword_escape
         redis.del "patern"
         redis.set "patern", patern_new
      end
      if redis.exists "count" then
         redis.del "count"
      end
      redirect_found '/'
    end

    get '/keyword/:keyword', set_name: true do
      redis = Redis.new(:host=>"127.0.0.1",:port=>6379,:driver => :hiredis)

      keyword = params[:keyword] or halt(400)

      entry = db.xquery(%| select * from entry where keyword = ? |, keyword).first or halt(404)
      entry[:stars] = load_stars(entry[:keyword])
      if redis.exists "content#{entry[:id]}" then
         entry[:html] = redis.get "content#{entry[:id]}"
      else 
         entry[:html] = htmlify(entry[:description])
         redis.set "content#{entry[:id]}",entry[:html]
      end

      locals = {
        entry: entry,
      }
      erb :keyword, locals: locals
    end

    post '/keyword/:keyword', set_name: true, authenticate: true do
      keyword = params[:keyword] or halt(400)
      is_delete = params[:delete] or halt(400)

      unless entry = db.xquery(%| SELECT id FROM entry WHERE keyword = ? |, keyword).first
        halt(404)
      end
      
      db.xquery(%| DELETE FROM entry WHERE keyword = ? |, keyword)
      #redisのパージを実行
      redis = Redis.new(:host=>"127.0.0.1",:port=>6379,:driver => :hiredis)
      redis.del "patern"
      if redis.exists "content#{entry[:id]}" then
         redis.del "content#{entry[:id]}"
         redis.del "patern"
         redis.del "url#{entry[:keyword]}"
         redis.del "anchor#{entry[:keyword]}"
      end
      if redis.exists "count" then
         redis.del "count"
      end
      redirect_found '/'
    end

    #add isutar
    get '/stars' do
        keyword = params[:keyword] || ''
        stars = db1.xquery(%| select * from star where keyword = ? |,keyword).to_a
        content_type :json
        JSON.generate(stars: stars)
    end

    post '/stars' do
        keyword = params[:keyword] || ''
#        isuda_keyword_url = URI(settings.isuda_origin)
#        isuda_keywrod_url.path = '/keyword/%s' % [Rack::Utils.escape_path(keyword)]
#        res = NET::HTTP.get_response(isuda_keyword_url)
#        halt(404) unless Net::HTTPSuccess === res

        user_name = params[:user]
        db1.xquery(%|
          INSERT INTO star (keyword, user_name, created_at)VALUES (?, ?, NOW())|, keyword, user_name)
        content_type :json
        JSON.generate(result: 'ok')
    end
  end
end


