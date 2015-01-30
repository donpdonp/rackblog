require 'json'
require 'slim'
require 'moneta'

class Rackblog
  def initialize
    Slim::Engine.set_options({pretty: true})
    @layout = Slim::Template.new('views/layout.slim')
    @article = Slim::Template.new('views/article.slim')
    @post = Slim::Template.new('views/post.slim')
    @db = Moneta.new(:LMDB, {dir: 'db'})
  end

  def call(env)
    req = Rack::Request.new(env)
    path = URI.decode(env['REQUEST_PATH'])
    puts "** db load #{env['REQUEST_PATH'].inspect} decode: #{path}"
    headers = {'Content-Type' => 'text/html'}

    key = path.split('/')[1]
    puts "Key #{key.inspect}"
    if key == 'post'
      if env['REQUEST_METHOD'] == 'GET'
        html = @post.render
      elsif env['REQUEST_METHOD'] == 'POST'
        slug = article_save(req.params)
        puts "Slug: #{slug}"
        post_url = "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}/#{slug}"
        puts "Redirect: #{post_url}"
        return [302, headers.merge({"Location" => post_url}), []]
      end
    elsif @db.key?(key)
      params = JSON.parse(@db[key])
      html = article(params)
    end

    if html
      ['200', headers, [html]]
    else
      ['404', headers, ['Page not found']]
    end
  end

  def article(params)
    @layout.render do |layout|
      @article.render(nil, params)
    end
  end

  def to_slug(str)
    str.gsub(' ','-')
  end

  def article_save(data)
    puts data.inspect
    slug = to_slug(data['title'])
    puts "Saving Key #{slug.inspect}"
    @db[slug] = data.to_json
    URI.encode(slug)
  end
end

