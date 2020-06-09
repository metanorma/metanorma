bundle update
bundle exec ruby yaml2xml.collection.rb collection1.yml > collection1.xml
bundle exec ruby collection-render.rb collection1.xml collection1
