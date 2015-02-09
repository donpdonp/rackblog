require 'time'
require 'json'
require 'bundler/setup'
require 'lmdb'
require 'pg'

lmdb = LMDB.new('db', {:mapsize => 10*1024*1024})
db = lmdb.database

conn = PG.connect( dbname: 'donpark_blog' )
conn.exec( "SELECT * FROM contents" ) do |result|
  result.each do |row|
    doc = {}
    now = Time.parse(row['published_at'])
    slug =  "/#{now.year}/#{"%02d"%now.month}/#{"%02d"%now.day}/#{row['permalink']}"
    doc['time'] = now.iso8601
    doc['title'] = row['title']
    doc['body'] = row['body']
    doc['tags'] = []
    puts "key: #{slug}"
    puts "val: #{doc.inspect}"
    db[slug] = doc.to_json
  end
end
