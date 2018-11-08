module Rackblog
  class Util
    def self.query_decode(query)
      URI.decode_www_form(query).reduce({}){|h, v| h[v[0]]=v[1]; h}
    end

    def self.safe_uri(url)
      begin
        uri = URI(url)
        if ['http', 'https'].include? uri.scheme
          uri
        end
      rescue
      end
    end

    def self.my_path(path)
      Util.path_prefix_remove(Rackblog::config[:url], path)
    end

    def self.path_prefix_remove(prefix_url, path)
      path.sub(/^#{URI(prefix_url).path}/, '/')
    end
  end
end