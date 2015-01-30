require 'slim'

class Rackblog
  def initialize
    Slim::Engine.set_options({pretty: true})
  end

  def call(env)
    template = template_for(env['REQUEST_PATH'])
    if template
      ['200', {'Content-Type' => 'text/html'}, [template.render]]
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

end
