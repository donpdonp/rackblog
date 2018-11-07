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
      Rackblog::config = @config = config
      @config[:url]+= "/" unless @config[:url][-1] == '/'
      Slim::Engine.set_options({pretty: true})
      @viewcache = {}
      lmdb = LMDB.new('db')
      @db = lmdb.database('blog', create:true)
      @tags = Tags.new(lmdb.database('tags', create:true))
      @tags.add_tag('__root')
      @mentions = lmdb.database('mentions', create:true)
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
      req = Request.new(env)
      puts "** req: #{req.verb} #{req.mime_accept} #{req.path.inspect} "+
           "=> parts #{req.path_parts} params #{req.params}"

      # response
      status = 200
      headers = {'Content-Type' => 'text/html'}
      body_parts = []

      if req.get? && req.path_parts.empty?
        body_parts.push(index(req.mime_accept))
      elsif req.get? && req.path_parts[0] == 'post'
        if auth_ok?(req)
          body_parts.push(layout('edit'))
        else
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        end
      elsif req.post? && req.path_parts[0] == 'post'
        if auth_ok?(req)
          slug = article_save(req.form)
          post_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{URI(@config[:url]).path}#{slug}"
          puts "Redirect: #{post_url}"
          return [302, headers.merge({"Location" => post_url}), []]
        else
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        end
      elsif req.path_parts[0] == 'tag'
        puts "Tag search #{req.path_parts[1]}"
        body_parts.push(tags(req.path_parts[1]))
      elsif req.path_parts[0] == 'tags'
        body_parts.push(tagviz(req.params, auth_ok?(req)))
      elsif req.path_parts[0] == 'admin'
        status, headers, body_parts = admin(req, status, headers, body_parts)
      elsif req.path_parts[0] == 'webmention'
        status, headers, body_parts = webmention(req, status, headers, body_parts)
      else
        article_path = req.path
        last_part = req.path_parts[-1]
        edit = last_part == 'edit'
        if edit
          article_path = '/'+req.path_parts[0, req.path_parts.length-1].join('/')
          puts "edit article path #{article_path}"
        end
        if last_part == 'delete' && auth_ok?(req)
          article_path = '/'+req.path_parts[0, req.path_parts.length-1].join('/')
          puts "delete article path #{article_path}"
          @db.delete(article_path)
          return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
        end
        json = @db.get(article_path)
        if json
          article = decode([req.path, json])
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
        body_parts.push("Page not found for #{req.path}")
      end

      [status, headers, body_parts]
    end
## End Routing

    def admin(req, status, headers, body_parts)
      if req.params['logout']
        Rack::Utils.delete_cookie_header!(headers, "rackblog", {:value => "",
                                                                :path => URI(@config[:url]).path})
        return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
      elsif auth_ok?(req)
        body_parts.push(layout('admin'))
      elsif req.params['token']
        auth_resp = HTTParty.post 'https://indieauth.com/auth',
                                 {query: {code: req.params['token'],
                                          redirect_uri: "#{@config[:url]}admin"}}
        auth = Util.query_decode(auth_resp.parsed_response)
        if auth['error']
          body_parts.push(auth['error_description'])
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
      [status, headers, body_parts]
    end

    def webmention(req, status, headers, body_parts)
      if req.get?
      end
      if req.post?
        #
        puts "lookingup target #{req.form["target"]}"
        path = URI(req.form["target"]).path
        article_path = Util.my_path(path)
        json = @db.get(article_path)
        if json
          puts "webmention article found #{article_path}"
          article = decode([req.path, json])
          mentions = JSON.parse(@mentions[article_path] || [].to_json)
          source = req.form["source"]
          mentions.push(source)
          puts "mentions #{mentions.to_json}"
          @mentions[article_path] = mentions.to_json
          status = 202
          body_parts.push('Accepted')
        else
          status = 400
        end
      end
      [status, headers, body_parts]
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

  class Request
    def initialize(env)
      rack_req = Rack::Request.new(env)
      path = Util.my_path(URI.decode(env['REQUEST_PATH']))
      @data = {
        path: path,
        params: Util.query_decode(env["QUERY_STRING"]),
        verb: env['REQUEST_METHOD'],
        mime_accept: env["HTTP_ACCEPT"].split(';')[0].split(',')[0],
        form: rack_req.params,
        cookies: rack_req.cookies
      }
    end

    def get?
      @data[:verb] == 'GET'
    end

    def post?
      @data[:verb] == 'POST'
    end

    def path
      @data[:path]
    end

    def path_parts
      parts = path.split('/')
      parts.shift
      parts
    end

    def params
      @data[:params]
    end

    def mime_accept
      @data[:mime_accept]
    end

    def verb
      @data[:verb]
    end

    def form
      @data[:form]
    end

    def cookies
      @data[:cookies]
    end

    def body
      @data[:body]
    end
  end

  class Util
    def self.query_decode(query)
      URI.decode_www_form(query).reduce({}){|h, v| h[v[0]]=v[1]; h}
    end

    def self.my_path(path)
      Util.path_prefix_remove(Rackblog::config[:url], path)
    end

    def self.path_prefix_remove(prefix_url, path)
      path.sub(/^#{URI(prefix_url).path}/, '/')
    end
  end
end
