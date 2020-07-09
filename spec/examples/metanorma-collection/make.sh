bundle update
bundle exec asciidoctor -b iso -r metanorma-iso rice-en.final.adoc
bundle exec asciidoctor -b iso -r metanorma-iso rice1-en.final.adoc
bundle exec asciidoctor -b iso -r metanorma-iso dummy.adoc
bundle exec ruby yaml2xml.collection.rb collection1.yml > collection1.xml
bundle exec ruby collection-render.rb collection1.xml collection_cover.html collection1
