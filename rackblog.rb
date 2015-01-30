require 'slim/include'

class Rackblog
  def initialize
    Slim::Engine.set_options({pretty: true})
    @layout = Slim::Template.new('views/layout.slim')
  end

  def call(env)
    template = template_for(env['REQUEST_PATH'])
    if template
      html = render(template)
      ['200', {'Content-Type' => 'text/html'}, [html]]
    else
      ['404', {'Content-Type' => 'text/html'}, ['Page not found']]
    end
  end

  def view_path(path)
    "views#{File.expand_path(path)}"
  end

  def template_for(path)
    view = view_path(path)
    if File.directory?(view)
      view += 'index'
    end
    view += '.slim'
    puts "testing #{view}"
    if File.exist?(view)
      puts "reading #{view}"
      Slim::Template.new(view)
    end
  end

  def render(template)
    puts "about to render"
    @layout.render do |layout|
      puts "i am layout block"
      template.render
    end
  end
end

module Helper
end
