require 'set'
require 'json'
require 'slim'
require 'lmdb'
require 'httparty'
require 'github/markdown'
require 'atom/feed'

module Rackblog
  class Server
    # Article
    # {"title"=>"I am title",
    #  "tags"=>["frog", "bed"],
    #  "body"=>"this is the body.",
    #  "time"=>"2015-02-08T17:04:23-08:00"}

    def initialize(config)
      @config = config
      @config[:url]+= "/" unless @config[:url][-1] == '/'
      Slim::Engine.set_options({pretty: true})
      @viewcache = {}
      lmdb = LMDB.new('db')
      @db = lmdb.database('blog', create:true)
      @tags = Tags.new(lmdb.database('tags', create:true))
      @tags.add_tag('__root')
      puts "Database connected with #{@db.stat[:entries]} posts and #{@tags.stat} tags on #{@config[:url]}"
    end

    def load_view(name)
      @viewcache[name] ||= {last: Time.parse('1990-01-01')}
      filename = "views/#{name}.slim"
      last = File.stat(filename).mtime
      if last > @viewcache[name][:last]
        puts "template cache load #{filename}"
        @viewcache[name][:template] = Slim::Template.new(filename)
        @viewcache[name][:last] = last
      end
      @viewcache[name][:template]
    end

## Routing
    def call(env)
      req = Rack::Request.new(env)
      path = my_path(URI.decode(env['REQUEST_PATH']))
      path_parts = path.split('/'); path_parts.shift
      qparams = query_decode(env["QUERY_STRING"])
      mime_accept = env["HTTP_ACCEPT"].split(';')[0].split(',')[0]
      puts "** req: #{mime_accept} #{env['REQUEST_PATH'].inspect} decode: #{path.inspect} => #{path_parts} #{qparams}"
      status = 200
      headers = {'Content-Type' => 'text/html'}
      body_parts = []

      if path == '/'
        body_parts.push(index(mime_accept))
      elsif path_parts[0] == 'post'
        if auth_ok?(req)
          if env['REQUEST_METHOD'] == 'GET'
            body_parts.push(layout('edit'))
          elsif env['REQUEST_METHOD'] == 'POST'
            slug = article_save(req.params)
            post_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{URI(@config[:url]).path}#{slug}"
            puts "Redirect: #{post_url}"
            return [302, headers.merge({"Location" => post_url}), []]
          end
        else
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        end
      elsif path_parts[0] == 'tag'
        puts "Tag search #{path_parts[1]}"
        body_parts.push(tags(path_parts[1]))
      elsif path_parts[0] == 'tags'
        body_parts.push(tagviz(qparams, auth_ok?(req)))
      elsif path_parts[0] == 'admin'
        puts "cookies: #{req.cookies.inspect}"
        if qparams['logout']
          Rack::Utils.delete_cookie_header!(headers, "rackblog", {:value => "",
                                                                  :path => URI(@config[:url]).path})
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        elsif auth_ok?(req)
          body_parts.push(layout('admin'))
        elsif qparams['token']
          resp = HTTParty.post 'https://indieauth.com/auth',
                                   {query: {code: qparams['token'],
                                            redirect_uri: "#{@config[:url]}admin"}}
          auth = query_decode(resp.parsed_response)
          if auth['error']
            html = auth['error_description']
          else
            Rack::Utils.set_cookie_header!(headers, "rackblog", {:value => @config[:apikey],
                                                                 :path => URI(@config[:url]).path,
                                                                 :expires => Time.now+(60*60*24*365)})
            return [302, headers.merge({"Location" => "#{@config[:url]}admin"}), []]
          end
        else
          qstr = URI.encode_www_form({:me=>@config[:indieauth],
                                      :redirect_uri=>"#{@config[:url]}admin"})
          auth_url = "https://indieauth.com/auth?#{qstr}"
          return [302, headers.merge({"Location" => auth_url}), []]
        end
      else
        edit = path_parts[-1] == 'edit'
        if edit
          path = '/'+path_parts[0, path_parts.length-1].join('/')
          puts "edit new path #{path}"
        end
        if path_parts[-1] == 'delete' && auth_ok?(req)
          path = '/'+path_parts[0, path_parts.length-1].join('/')
          @db.delete(path)
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        end
        json = @db.get(path)
        if json
          article = decode([path, json])
          if edit && auth_ok?(req)
            body_parts.push(layout('edit', {article: article}))
          else
            article['tags'].map!{|t| @tags.tag_parents(t)}
            body_parts.push(layout('article', {article: article}))
          end
        end
      end

      if body_parts.empty?
        status = 404
        body_parts.push("Page not found for #{path}")
      end

      [status, headers, body_parts]
    end
## End Routing

    def my_path(path)
      path.sub(/^#{URI(@config[:url]).path}/, '/')
    end

    def auth_ok?(req)
      @config[:apikey] && req.cookies['rackblog'] == @config[:apikey]
    end

    def tags(tag)
     children = @tags.tag_children(tag)
     articles = []
      count = @db.stat[:entries]
      if count > 0
        start = Time.now
        # table scan
        @db.cursor do |cursor|
          record = cursor.last
          while record do
            article = decode(record)
            if article['tags'].to_set.intersect?(children.to_set)
              articles << article
            end
            record = cursor.prev
          end
        end
        puts "Scanned #{count} articles for tag #{tag}. #{articles.size} found. #{"%0.2f"%(Time.now-start)} seconds."
      end
      layout('index', {articles: articles, name: @config[:name] })
    end

    def tagviz(params, auth_good)
      if auth_good
        if params['add']
          if params['parent']
            @tags.add_tag(params['add'], params['parent'])
          else
            @tags.add_tag(params['add'])
          end
        end
        if params['del']
          del_tag(params['del'])
        end
      end
      tags = @tags.load_tags(params['start'])
      puts "tagviz #{tags.inspect}"
      layout('tags', {tags: tags})
    end

    def index(mime)
      articles = []
      if @db.stat[:entries] > 0
        records = []
        @db.cursor do |cursor|
          records << cursor.last if records.empty?
          loop do
            next_art = cursor.prev
            break unless next_art
            records << next_art
          end
        end
        articles = records.map{|record| decode(record)}
      end
      if mime == "text/html"
        decode_list_html(articles)
      elsif mime == "application/atom+xml"
        decode_list_atom(articles)
      end
    end

    def decode(record)
      article = JSON.parse(record[1])
      # convert date str into ruby date object
      article['time'] = Time.parse(article['time'])
      # url is determined at runtime
      article['url'] = @config[:url]+record[0].sub(/^\//,'')
      article
    end

    def decode_list_html(articles)
      layout('index', {articles: articles, name: @config[:name] })
    end

    def decode_list_atom(articles)
      feed = Atom::Feed.new
      articles.each do |article|
        post = Atom::Entry.new
        post.title = article['title']
        post.content = article['body']
        post.content.type = "html"
        feed.entries << post
      end
      feed.to_s
    end

    def layout(template_name, params = {})
      params.merge!({prefix: URI(@config[:url]).path})
      layout_params = params.merge({name: @config[:name],
                                    slogan: @config[:slogan]})
      load_view('layout').render(nil, layout_params) do |layout|
        load_view(template_name).render(nil, params)
      end
    end

    def to_slug(str)
      str.gsub(' ','-').downcase
    end

    def query_decode(query)
      URI.decode_www_form(query).reduce({}){|h, v| h[v[0]]=v[1]; h}
    end

    def article_save(data)
      now = Time.now
      data['time'] ||= now.iso8601
      data['tags'] = data['tags'].split(' ').map{|t| t.strip}
      data['title'].strip!
      data['slug'] ||= to_slug("/#{now.year}/#{"%02d"%now.month}/#{"%02d"%now.day}/#{data['title']}")
      puts "Saving Key #{data['slug'].inspect} => #{data.to_json}"
      @db[data['slug']] = data.to_json
      URI.encode(data['slug'][1,data['slug'].length-1])
    end
  end
end
