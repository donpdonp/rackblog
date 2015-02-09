require 'json'
require 'slim'
require 'lmdb'
require 'httparty'
require 'github/markdown'

class Rackblog
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
    @db = lmdb.database
    puts "Database connected with #{@db.stat[:entries]} posts on #{@config[:url]}"
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

  def call(env)
    req = Rack::Request.new(env)
    path = my_path(URI.decode(env['REQUEST_PATH']))
    path_parts = path.split('/'); path_parts.shift
    qparams = query_decode(env["QUERY_STRING"])
    puts "** req: #{env["HTTP_ACCEPT"].split(';')[0].split(',')[0]} #{env['REQUEST_PATH'].inspect} decode: #{path.inspect} => #{path_parts} #{qparams}"
    headers = {'Content-Type' => 'text/html'}

    if path == '/'
      html = index
    elsif path_parts[0] == 'post'
      if auth_ok?(req)
        if env['REQUEST_METHOD'] == 'GET'
          html = layout('post')
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
      html = tags(path_parts[1])
    elsif path_parts[0] == 'admin'
      puts "cookies: #{req.cookies.inspect}"
      if qparams['logout']
        Rack::Utils.delete_cookie_header!(headers, "rackblog", {:value => "",
                                                                :path => URI(@config[:url]).path})
        return [302, headers.merge({"Location" => "#{@config[:url]}"}), []]
      elsif auth_ok?(req)
        html = layout('admin')
      elsif qparams['token']
        resp = HTTParty.post 'https://indieauth.com/auth',
                                 {query: {code: qparams['token'],
                                          redirect_uri: "#{@config[:url]}admin"}}
        auth = query_decode(resp.parsed_response)
        if auth['error']
          html = auth['error_description']
        else
          Rack::Utils.set_cookie_header!(headers, "rackblog", {:value => @config[:apikey],
                                                               :path => URI(@config[:url]).path})
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
      json = @db.get(path)
      if json
        article = decode([path, json])
        if edit && auth_ok?(req)
          html = layout('post', {article: article[1]})
        else
          html = layout('article', {article: article[1]})
        end
      end
    end

    if html
      ['200', headers, [html]]
    else
      ['404', headers, ['Page not found']]
    end
  end

  def my_path(path)
    path.sub(/^#{URI(@config[:url]).path}/, '/')
  end

  def auth_ok?(req)
    @config[:apikey] && req.cookies['rackblog'] == @config[:apikey]
  end

  def tags(tag)
    articles = []
    count = @db.stat[:entries]
    if count > 0
      start = Time.now
      # table scan
      @db.cursor do |cursor|
        record = cursor.last
        while record do
          article = decode(record)
          if article[1]['tags'].include?(tag)
            articles << article
          end
          record = cursor.prev
        end
      end
      puts "Scanned #{count} articles for tag #{tag}. #{articles.size} found. #{"%0.2f"%(Time.now-start)} seconds."
    end
    layout('index', {articles: articles})
  end

  def index(start = nil)
    records = []
    if @db.stat[:entries] > 0
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
    layout('index', {articles: articles})
  end

  def decode(record)
    article = JSON.parse(record[1])
    article['time'] = Time.parse(article['time'])
    full = @config[:url]+record[0].sub(/^\//,'')
    [full, article]
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

