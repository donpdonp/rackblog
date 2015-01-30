require 'json'
require 'slim'
require 'lmdb'

class Rackblog
  def initialize
    Slim::Engine.set_options({pretty: true})
    @layout = Slim::Template.new('views/layout.slim')
    @article = Slim::Template.new('views/article.slim')
    @post = Slim::Template.new('views/post.slim')
    @index = Slim::Template.new('views/index.slim')
    lmdb = LMDB.new('db')
    @db = lmdb.database
  end

  def call(env)
    req = Rack::Request.new(env)
    path = URI.decode(env['REQUEST_PATH'])
    puts "** db load #{env['REQUEST_PATH'].inspect} decode: #{path}"
    headers = {'Content-Type' => 'text/html'}

    if path == '/'
      html = index
    elsif path.split('/')[1] == 'post'
      if env['REQUEST_METHOD'] == 'GET'
        html = @post.render
      elsif env['REQUEST_METHOD'] == 'POST'
        slug = article_save(req.params)
        puts "Slug: #{slug}"
        post_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}#{slug}"
        puts "Redirect: #{post_url}"
        return [302, headers.merge({"Location" => post_url}), []]
      end
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

  def index
    articles = []
    puts @db.stat.inspect
    if @db.stat[:entries] > 0
      @db.cursor do |cursor|
        articles << cursor.last if articles.empty?
        15.times do
          next_art = cursor.prev
          if next_art
            next_art[1] = JSON.parse(next_art[1])
            articles << next_art
          else
            break
          end
        end
      end
    end
    puts articles.inspect
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

