require 'time'
require 'json'
require 'bundler/setup'
require 'lmdb'
require 'pg'

lmdb = LMDB.new('db', {:mapsize => 10*1024*1024})
db = lmdb.database

def todoc(row)
    doc = {}
    now = Time.parse(row['published_at'])
    slug =  "/#{now.year}/#{"%02d"%now.month}/#{"%02d"%now.day}/#{row['permalink']}"
    doc['slug'] = slug
    doc['time'] = now.iso8601
    doc['title'] = row['title']
    doc['body'] = row['body']
    doc['tags'] = []
    doc
end

conn = PG.connect( dbname: 'donpark_blog' )
conn.exec( "SELECT * FROM contents" ) do |result|
  result.each do |row|
    if row['type'] == "Article"
      doc = todoc(row)
      db[doc['slug']] = doc.to_json
      puts "#{doc['slug']}"
    else
      puts "Skipping post type #{row['type']}"
    end
  end
end
