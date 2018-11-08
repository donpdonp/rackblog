module Rackblog
  class Webmention
    def self.dispatch(req, status, headers, body_parts)
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
                mentions.push({source: source})
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

    def self.backfill(req, status, headers, body_parts)
      Rackblog.Mentions.each do |mention_kv|
        target = "#{Rackblog.Config[:url]}#{mention_kv[0]}"
        puts "webmentions for #{target}"
        mentions = JSON.parse(mention_kv[1])
        mentions.each do |mention|
          begin
            doc = self.microformat_get(mention['source'])
            entries = self.has_reply_to(doc, 'h-entry', target)
            puts "- #{mention['source']} -> h-entry #{entries.inspect} (text was #{mention['text']})"
            if entries.length > 0
              mention['text'] = entries.join(' ')
            end
          rescue StandardError => e
            puts "#{e} #{mention['source']}"
          end
        end
        Rackblog.Mentions[mention_kv[0]] = mentions.to_json
      end
      body_parts.push("backfill checked #{Rackblog.Mentions.size} webmentions")
      [status, headers, body_parts]
    end

    def self.microformat_get(url)
      puts "get #{url}"
      resp = HTTParty.get url
      Nokogiri::HTML(resp.body)
    end

    def self.has_reply_to(doc, mf_tag, reply_url)
      doc.css(".#{mf_tag}").map do |entry|
        if entry.css(".u-in-reply-to[href='#{reply_url}']").size > 0
          econtent = entry.css(".e-content > text()").first
          text = econtent.text.chomp('')
          if text.empty?
            epcontent = entry.css(".e-content > p > text()").first
            text = epcontent.text.chomp('')
          end
          puts "** text #{text}"
          text
        end
      end.compact
    end

  end
end
