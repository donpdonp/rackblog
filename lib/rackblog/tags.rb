module Rackblog
  class Tags
    def initialize(db)
      @tags = db
      add_tag('__root')
    end

    def stat
      @tags.stat[:entries]
    end

    def tag_parents(name, parents = [])
      parents << name
      tag = load_tag(name)
      if tag && tag[:parent] != '__root'
        tag_parents(tag[:parent], parents)
      else
        parents
      end
    end

    def tag_children(name)
    # {:name=>"blockchain", :parent=>"cryptocurrency", :children=>[]}]}
      children = []
      tag = load_tag(name)
      if tag
       children = [name]
       tag[:children].each{|child| children += tag_children(child) }
      end
      children
    end

    def load_tags(name)
      name = '__root' if name.nil?
      tag = load_tag(name)
      tag[:children].map!{|tag| load_tags(tag)}.compact! if tag
      tag
    end

    def load_tag(name='__root')
      json = @tags[name]
      json && JSON.parse(json, {symbolize_names:true})
    end

    def add_tag(name, parent='__root')
      puts "add_tag #{name} to #{parent}"
      tag = load_tag(name)
      if tag
        puts "tag #{name} already exists #{tag.inspect}"
      else
        parent = nil if name == '__root'
        if parent
          puts "parent check #{parent}"
          parent_tag = load_tag(parent)
          if parent_tag
            parent_tag[:children] << name
            puts "parent tag fixup #{parent_tag.inspect}"
            @tags[parent] = parent_tag.to_json
          else
            puts "missing parent #{parent}!"
            return
          end
        end
        puts "creating tag #{name.inspect} parent #{parent.inspect}"
        @tags[name] = blank_tag(name, parent).to_json
      end
    end

    def del_tag(name)
      tag = load_tag(name)
      if tag
        parent = load_tag(tag[:parent])
        if parent
          parent[:children] -= [name]
          @tags[parent[:name]] = parent.to_json
        end
        puts @tags.delete(name)
      end
    end

    def blank_tag(name, parent)
      {name: name, parent: parent, children: []}
    end
  end
end
