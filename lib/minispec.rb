module MiniSpec
  def self.classify(description)
    description.gsub(/[^a-zA-Z0-9 ]/, '').gsub(/((^| )\w)/) { $1.upcase.strip }
  end

  def self.included(klass)
    klass.send(:extend,  MiniSpec::DSL)
    klass.send(:include, MiniSpec::Hooks)
    klass.send(:include, MiniSpec::Expectations)
  end

  AssertionContext = Class.new { include Test::Unit::Assertions }.new

  def setup
    AssertionContext._assertions = 0
    super
  end

  def teardown
    self._assertions += AssertionContext._assertions
    super
  end

  class Expectation < Struct.new(:value)
    class Method
      def initialize(expectation_method, args)
        @method = expectation_method
        @method << '?' unless expectation_method[-1, 1] == '?'
        @args = args
      end
      def ===(object)
        object.send(@method, *@args)
      end
    end

    class Error < Expectation
      def ===(block)
        AssertionContext.assert_raises value, &block
      end
    end

    class Change < Expectation
      def from(val)
        @from = val
      end
      def ===(block)
        block.call
        value.call == @from
      end
    end

    class Eql < Expectation
      def ===(other)
        value.eql? other
      end
    end

    class Equal < Expectation
      def ==(other)
        AssertionContext.assert_equal value, other
      end
      alias === ==
    end

    class NotEqual < Expectation
      def ==(other)
        AssertionContext.refute_equal value, other
      end
      alias === ==
    end
  end

  module Should
    def should(matcher = nil)
      if matcher
        AssertionContext.assert_operator matcher, :===, self
      else
        Expectation::Equal.new(self)
      end
    end
  end

  module ShouldNot
    def should_not(matcher = nil)
      if matcher
        AssertionContext.refute_operator matcher, :===, self
      else
        Expectation::NotEqual.new(self)
      end
    end
  end

  module Hooks
    def self.included(klass)
      klass.send(:instance_variable_set, :@before_hooks, [])
      klass.send(:instance_variable_set, :@after_hooks, [])
      klass.extend ClassMethods
    end

    def setup
      super
      self.class.instance_variable_get(:@before_hooks).each do |blk|
        instance_eval &blk
      end
    end

    def teardown
      super
      self.class.ancestors[1].instance_variable_get(:@after_hooks).each do |blk|
        instance_eval &blk
      end
    end

    module ClassMethods
      def inherited(klass)
        super
        klass.send(:instance_variable_set, :@before_hooks, @before_hooks.dup)
        klass.send(:instance_variable_set, :@after_hooks, @after_hooks.dup)
      end

      def before(*args, &block)
        @before_hooks << block
      end

      def after(*args, &block)
        @after_hooks << block
      end
    end
  end

  module DSL
    def context(description, &block)
      klass = Class.new(self, &block)
      const_set(MiniSpec.classify(description), klass)
    end
    alias describe context

    def it(name, &block)
      define_method "test_#{name.downcase.gsub(/\W+/, '_')}", &block
    end
  end

  module Expectations

    def include(substring)
      Regexp.new(substring)
    end

    def running(&block)
      block
    end

    def change(&block)
      Expectation::Change.new(block)
    end

    def eql(value)
      Expectation::Eql.new(value)
    end

    def raise_error(type)
      Expectation::Error.new(type)
    end

    def be_true
      true
    end

    def be_nil
      nil
    end

    def be_false
      false
    end

    def method_missing(name, *args)
      if name.to_s =~ /be_(?:an?_)?(.*)/
        Expectation::Method.new($1, args)
      else
        super
      end
    end
  end
end

class Object
  include MiniSpec::Should
  include MiniSpec::ShouldNot
end

class Test::Unit::TestCase
  include MiniSpec
end

def describe(description, &block)
  Module.const_set(MiniSpec.classify(description), Class.new(Test::Unit::TestCase, &block))
end
