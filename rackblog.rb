require 'json'
require 'slim'
require 'lmdb'

class Rackblog
  def initialize(config)
    @config = config
    load_views
    lmdb = LMDB.new('db')
    @db = lmdb.database
    puts "Database connected with #{@db.stat[:entries]} posts on #{@config[:prefix]}"
  end

  def load_views
    Slim::Engine.set_options({pretty: true})
    @layout = Slim::Template.new('views/layout.slim')
    @article = Slim::Template.new('views/article.slim')
    @post = Slim::Template.new('views/post.slim')
    @index = Slim::Template.new('views/index.slim')
  end

  def call(env)
    req = Rack::Request.new(env)
    path = my_path(URI.decode(env['REQUEST_PATH']))
    path_parts = path.split('/'); path_parts.shift
    puts "** db load #{env['REQUEST_PATH'].inspect} decode: #{path} #{path_parts}"
    headers = {'Content-Type' => 'text/html'}

    if path == '/'
      html = index
    elsif path_parts[0] == 'post'
      if env['REQUEST_METHOD'] == 'GET'
        html = @post.render
      elsif env['REQUEST_METHOD'] == 'POST'
        slug = article_save(req.params)
        puts "Slug: #{slug}"
        post_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{@config[:prefix]}#{slug}"
        puts "Redirect: #{post_url}"
        return [302, headers.merge({"Location" => post_url}), []]
      end
    elsif path_parts[0] == 'tag'
      puts "Tag search #{path_parts[1]}"
      html = tags(path_parts[1])
    else
      json = @db.get(path)
      if json
        params = JSON.parse(json)
        html = layout(@article, params)
      end
    end

    if html
      ['200', headers, [html]]
    else
      ['404', headers, ['Page not found']]
    end
  end

  def my_path(path)
    if @config[:prefix]
      new_path = path.sub(/#{@config[:prefix]}/,'')
      new_path = "/" if new_path.empty?
      new_path
    else
      path
    end
  end

  def tags(tag)
    articles = []
    layout(@index, {articles: articles})
  end

  def index(start = nil)
    articles = []
    if @db.stat[:entries] > 0
      @db.cursor do |cursor|
        articles << cursor.last if articles.empty?
        15.times do
          next_art = cursor.prev
          if next_art
            articles << next_art
          else
            break
          end
        end
      end
      articles.each do |a|
        a[0]="#{@config[:prefix]}#{a[0]}"
        a[1]=JSON.parse(a[1])
      end
    end
    layout(@index, {articles: articles})
  end

  def layout(template, params)
    @layout.render do |layout|
      template.render(nil, params)
    end
  end

  def to_slug(str)
    str.gsub(' ','-')
  end

  def article_save(data)
    puts data.inspect
    now = Time.now
    data['time'] = now.iso8601
    slug = to_slug("/#{now.year}/#{"%02d"%now.month}/#{"%02d"%now.day}/#{data['title']}")
    puts "Saving Key #{slug.inspect}"
    @db[slug] = data.to_json
    URI.encode(slug)
  end

end

