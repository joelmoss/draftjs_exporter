# frozen_string_literal: true

module DraftjsExporter
  class WrapperState
    def initialize(block_map, blocks)
      @block_map = block_map
      @blocks = blocks
      @wrappers = []
      @document = Nokogiri::HTML::Document.new
      @document.encoding = 'UTF-8' # To not transform HTML entities
      @fragment = Nokogiri::HTML::DocumentFragment.new(document)

      reset_wrapper
    end

    def element_for(block)
      type = block.fetch(:type, 'unstyled')
      unstyled_options = block_map['unstyled']

      return create_element block, block_map.fetch(type, unstyled_options) unless type == 'atomic'

      if (klass = atomic_class(block[:data][:type]))
        klass.create(document, block, @blocks).tap do |e|
          parent_for(block, {}).add_child e
        end
      else
        create_element block, unstyled_options
      end
    end

    def to_s
      to_html
    end

    def to_html(options = {})
      fragment.to_html(options)
    end

    private

    attr_reader :fragment, :document, :block_map, :wrapper

    def clear_wrappers
      @wrappers = []
    end

    def set_wrapper(element, options = {}, should_nest: false)
      @wrappers[
        should_nest ? @wrappers.length : 0
      ] = [element, options]
    end

    def wrapper_element
      @wrappers.last[0] || fragment
    end

    def wrapper_options
      @wrappers.last[1]
    end

    def create_element(block, block_options)
      document.create_element(
        block_options[:element],
        block_options.fetch(:prefix, ''),
        block_options.fetch(:attrs, {})
      ).tap do |e|
        parent_for(block, block_options).add_child(e)
      end
    end

    def parent_for(block, options)
      return reset_wrapper unless options.key?(:wrapper)

      if options[:wrapper].is_a?(Class)
        wrapper_class = options.delete(:wrapper)
        options[:wrapper] = { element: wrapper_class }
      end

      new_options = [options[:wrapper][:element], options[:wrapper].fetch(:attrs, {})]
      depth = can_nest? ? block[:depth] : 0

      create_wrapper(new_options, block, should_nest: false) if new_options != wrapper_options && depth.zero?

      level_difference = depth - (@wrappers.length - 1)

      if level_difference.positive?
        create_wrapper(new_options, block, should_nest: true)
      else
        @wrappers.pop(-level_difference)
      end

      wrapper_element
    end

    def reset_wrapper
      clear_wrappers
      set_wrapper(fragment)
      wrapper_element
    end

    def create_wrapper(options, block, should_nest: true)
      new_element = if options.first.is_a?(Class)
                      wrapper = options.first
                      wrapper.create(document, block)
                    else
                      document.create_element(*options)
                    end

      target_wrapper = if should_nest
                         if !wrapper_element.children.empty?
                           wrapper_element.children.last
                         else
                           wrapper_element
                         end
                       else
                         reset_wrapper
                       end

      target_wrapper.add_child(new_element)
      set_wrapper new_element, options, should_nest: should_nest
    end

    def atomic_class(name)
      return unless name

      klass = "DraftjsExporter::Atomic::#{name.classify}"

      begin
        klass.constantize
      rescue NameError
        nil
      end
    end

    def can_nest?
      wrapper_element != fragment
    end
  end
end
