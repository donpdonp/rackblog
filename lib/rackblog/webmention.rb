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
              if mentions.map {|m| m['source']}.include?(source.to_s)
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
            doc = self.html_load(mention['source'])
            reply_to_text = self.reply_to_text(doc, target)
            if reply_to_text
              reply_blob = {text: reply_to_text, author: { url: "", name: ""}}
              puts "reply_to = #{reply_blob.to_json}"
              mention['reply_to'] = reply_blob
            end
            like_of = self.like_of(doc, target)
            if like_of
              like_blob = {author: { url: "", name: ""}}
              puts "like = #{like_blob.to_json}"
              mention['like'] = like_blob
            end
          rescue SocketError => e
            puts "#{e} #{mention['source']}"
          end
        end
        Rackblog.Mentions[mention_kv[0]] = mentions.to_json
      end
      body_parts.push("backfill checked #{Rackblog.Mentions.size} webmentions")
      [status, headers, body_parts]
    end

    def self.html_load(url)
      puts "get #{url}"
      resp = HTTParty.get url
      Nokogiri::HTML(resp.body)
    end

    def self.like_of(doc, target)
      likes = doc.css(".h-entry").map do |entry|
        like = self.has_like_of(entry, target)
        puts "- #{entry.name} .#{entry.attributes['class']} has like #{like.inspect}"
        like
      end
      likes.select{|l| l}.length > 0
    end

    def self.has_like_of(entry, target)
      entry.css(".u-like-of").length > 0 #mf2 ambiguity
    end

    def self.reply_to_text(doc, target)
      entries = doc.css(".h-entry").map do |entry|
        text = self.has_reply_to(entry, target)
        puts "- #{entry.name} .#{entry.attributes['class']} has text #{text.inspect}"
        text
      end
      if entries.compact.length > 0
        entries.join(' ')
      end
    end

    def self.has_reply_to(entry, reply_url)
      if entry.css(".u-in-reply-to[href='#{reply_url}']").size > 0
        econtent = entry.css(".e-content > text()").first
        text = econtent.text.chomp('')
        if text.empty?
          epcontent = entry.css(".e-content > p > text()").first
          text = epcontent.text.chomp('')
        end
        text
      end
    end

  end
end
