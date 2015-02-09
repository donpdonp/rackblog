require 'json'
require 'slim'
require 'lmdb'

class Rackblog
  # Article
  # {"title"=>"I am title",
  #  "tags"=>["frog", "bed"],
  #  "body"=>"this is the body.",
  #  "time"=>"2015-02-08T17:04:23-08:00"}

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
        html = layout(@post)
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
        article = decode([path, json])
        puts article.inspect
        html = layout(@article, {article: article[1], prefix: @config[:prefix]})
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
    layout(@index, {articles: articles, prefix: @config[:prefix]})
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
    layout(@index, {articles: articles, prefix: @config[:prefix]})
  end

  def decode(record)
    [record[0], JSON.parse(record[1])]
  end

  def layout(template, params = {})
    params.merge!({prefix: @config[:prefix]})
    @layout.render(nil, params) do |layout|
      template.render(nil, params)
    end
  end

  def to_slug(str)
    str.gsub(' ','-')
  end

  def article_save(data)
    puts "article_save: #{data.inspect}"
    now = Time.now
    data['time'] ||= now.iso8601
    data['tags'] = data['tags'].split(' ').map{|t| t.strip}
    slug = to_slug("/#{now.year}/#{"%02d"%now.month}/#{"%02d"%now.day}/#{data['title']}")
    puts "wtf tags #{data['tags'].inspect}"
    puts "Saving Key #{slug.inspect} => #{data.to_json}"
    @db[slug] = data.to_json
    URI.encode(slug)
  end

end

