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
    puts "db load #{env['REQUEST_PATH'].inspect}"
    key = env['REQUEST_PATH']
    if key == '/post'
      html = @post.render
    elsif @db.key?(key)
      html = article(@db[key])
    end
    if html
      ['200', {'Content-Type' => 'text/html'}, [html]]
    else
      ['404', {'Content-Type' => 'text/html'}, ['Page not found']]
    end
  end

  def article(markdown)
    @layout.render do |layout|
      @article.render do |article|
        markdown
      end
    end
  end
end

module Helper
end
