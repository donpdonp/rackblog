module Rackblog
#  class Webmention
    def self.webmention(req, status, headers, body_parts)
      if req.get?
      end
      if req.post?
        target = Util.safe_uri(req.form["target"])
        if target
          path = target.path
          article_path = Util.my_path(path)
          json = Rackblog.Db.get(article_path)
          if json
            puts "webmention article found #{article_path}"
            mentions = self.mentions(article_path)
            source = Util.safe_uri(req.form["source"])
            if source
              if mentions.include?(source.to_s)
                puts "dupe source ignored: #{source}"
              else
                mentions.push(source.to_s)
              end
              puts "mentions: #{mentions.to_json}"
              Rackblog.Mentions[article_path] = mentions.to_json
              status = 202
              body_parts.push('Accepted')
            else
              puts "webmention bad source #{source}"
              status = 400
            end
          else
            puts "webmention article not found #{article_path}"
            status = 400
          end
        else
          puts "webmention bad target #{target}"
          status = 400
        end
      end
      [status, headers, body_parts]
    end

    def self.mentions(slug)
      JSON.parse(Rackblog.Mentions[slug] || [].to_json)
    end
#  end
end
