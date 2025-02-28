# frozen_string_literal: true

require "liquid"

module Metanorma
  module Compile
    class RelatonDrop < Liquid::Drop
      def initialize(relaton_data)
        @relaton = relaton_data
      end

      def docidentifier
        at("./docidentifier")
      end

      def title
        at("./title")
      end

      def date
        at("./date/on")
      end

      def publisher
        at("./contributor[role/@type = 'publisher']/organization/name")
      end

      def language
        at("./language")
      end

      def script
        at("./script")
      end

      def version
        at("./version")
      end

      def slugify
        docidentifier&.downcase
          &.gsub(/[^a-z0-9]+/, "-")
          &.gsub(/-+/, "-")
          &.gsub(/^-|-$/, "")
      end

      private

      def at(xpath)
        @relaton.at(xpath)&.text
      end
    end
  end
end
