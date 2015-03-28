require 'test_helper'
require 'mocha/setup'
require 'action_view'
require 'action_view/testing/resolvers'
require 'active_support/cache'
require 'jbuilder/jbuilder_template'

BLOG_POST_PARTIAL = <<-JBUILDER
  json.extract! blog_post, :id, :body
  json.author do
    name = blog_post.author_name.split(nil, 2)
    json.first_name name[0]
    json.last_name  name[1]
  end
JBUILDER

COLLECTION_PARTIAL = <<-JBUILDER
  json.extract! collection, :id, :name
JBUILDER

BlogPost = Struct.new(:id, :body, :author_name)
Collection = Struct.new(:id, :name)
blog_authors = [ 'David Heinemeier Hansson', 'Pavel Pravosud' ].cycle
BLOG_POST_COLLECTION = 10.times.map{ |i| BlogPost.new(i+1, "post body #{i+1}", blog_authors.next) }
COLLECTION_COLLECTION = 5.times.map{ |i| Collection.new(i+1, "collection #{i+1}") }

ActionView::Template.register_template_handler :jbuilder, JbuilderHandler

module Rails
  def self.cache
    @cache ||= ActiveSupport::Cache::MemoryStore.new
  end
end

class JbuilderTemplateTest < ActionView::TestCase
  setup do
    @context = self
    Rails.cache.clear
  end

  def partials
    {
      '_partial.json.jbuilder'  => 'foo ||= "hello"; json.content foo',
      '_blog_post.json.jbuilder' => BLOG_POST_PARTIAL,
      '_collection.json.jbuilder' => COLLECTION_PARTIAL
    }
  end

  def render_jbuilder(source)
    @rendered = []
    lookup_context.view_paths = [ActionView::FixtureResolver.new(partials.merge('test.json.jbuilder' => source))]
    ActionView::Template.new(source, 'test', JbuilderHandler, :virtual_path => 'test').render(self, {}).strip
  end

  def undef_context_methods(*names)
    self.class_eval do
      names.each do |name|
        undef_method name.to_sym if method_defined?(name.to_sym)
      end
    end
  end

  def assert_collection_rendered(json, context = nil)
    result = MultiJson.load(json)
    result = result.fetch(context) if context

    assert_equal 10, result.length
    assert_equal Array, result.class
    assert_equal 'post body 5',        result[4]['body']
    assert_equal 'Heinemeier Hansson', result[2]['author']['last_name']
    assert_equal 'Pavel',              result[5]['author']['first_name']
  end

  test 'rendering' do
    json = render_jbuilder <<-JBUILDER
      json.content 'hello'
    JBUILDER

    assert_equal 'hello', MultiJson.load(json)['content']
  end

  test 'key_format! with parameter' do
    json = render_jbuilder <<-JBUILDER
      json.key_format! :camelize => [:lower]
      json.camel_style 'for JS'
    JBUILDER

    assert_equal ['camelStyle'], MultiJson.load(json).keys
  end

  test 'key_format! propagates to child elements' do
    json = render_jbuilder <<-JBUILDER
      json.key_format! :upcase
      json.level1 'one'
      json.level2 do
        json.value 'two'
      end
    JBUILDER

    result = MultiJson.load(json)
    assert_equal 'one', result['LEVEL1']
    assert_equal 'two', result['LEVEL2']['VALUE']
  end

  test 'partial! renders partial' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'partial'
    JBUILDER

    assert_equal 'hello', MultiJson.load(json)['content']
  end

  test 'partial! + locals via :locals option' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'partial', locals: { foo: 'howdy' }
    JBUILDER

    assert_equal 'howdy', MultiJson.load(json)['content']
  end

  test 'partial! + locals without :locals key' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'partial', foo: 'goodbye'
    JBUILDER

    assert_equal 'goodbye', MultiJson.load(json)['content']
  end

  test 'partial! + block' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', blog_post: BLOG_POST_COLLECTION.first do
        json.favs 18
      end
    JBUILDER

    post = BLOG_POST_COLLECTION.first
    assert_equal post.id, MultiJson.load(json)['id']
    assert_equal 18, MultiJson.load(json)['favs']
  end

  test 'partial! renders collections' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', :collection => BLOG_POST_COLLECTION, :as => :blog_post
    JBUILDER

    assert_collection_rendered json
  end

  test 'partial! renders collections with block' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', :collection => BLOG_POST_COLLECTION, :as => :blog_post do
        json.favs 18
      end
    JBUILDER

    assert_collection_rendered json

    MultiJson.load(json).each do |post_json|
      assert_equal 18, post_json['favs']
    end
  end

  test 'partial! renders collections with block with parameter' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', :collection => BLOG_POST_COLLECTION, :as => :blog_post do |post|
        json.color %w(red green yellow)[post.id % 3]
      end
    JBUILDER

    assert_collection_rendered json

    MultiJson.load(json).each do |post_json|
      expected_color = %w(red green yellow)[post_json['id'] % 3]
      assert_equal expected_color, post_json['color']
    end
  end

  test 'partial! renders collections when as argument is a string' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', collection: BLOG_POST_COLLECTION, as: "blog_post"
    JBUILDER

    assert_collection_rendered json
  end

  test 'partial! renders collections as collections' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'collection', collection: COLLECTION_COLLECTION, as: :collection
    JBUILDER

    assert_equal 5, MultiJson.load(json).length
  end

  test 'partial! renders as empty array for nil-collection' do
    json = render_jbuilder <<-JBUILDER
      json.partial! 'blog_post', :collection => nil, :as => :blog_post
    JBUILDER

    assert_equal '[]', json
  end

  test 'partial! renders collection (alt. syntax)' do
    json = render_jbuilder <<-JBUILDER
      json.partial! :partial => 'blog_post', :collection => BLOG_POST_COLLECTION, :as => :blog_post
    JBUILDER

    assert_collection_rendered json
  end

  test 'partial! renders as empty array for nil-collection (alt. syntax)' do
    json = render_jbuilder <<-JBUILDER
      json.partial! :partial => 'blog_post', :collection => nil, :as => :blog_post
    JBUILDER

    assert_equal '[]', json
  end

  test 'render array of partials' do
    json = render_jbuilder <<-JBUILDER
      json.array! BLOG_POST_COLLECTION, :partial => 'blog_post', :as => :blog_post
    JBUILDER

    assert_collection_rendered json
  end

  test 'render array of partials with block' do
    json = render_jbuilder <<-JBUILDER
      json.array! BLOG_POST_COLLECTION, :partial => 'blog_post', :as => :blog_post do
        json.favs 18
      end
    JBUILDER

    assert_collection_rendered json
    MultiJson.load(json).each do |post_json|
      assert_equal 18, post_json['favs']
    end
  end

  test 'render array of partials as empty array with nil-collection' do
    json = render_jbuilder <<-JBUILDER
      json.array! nil, :partial => 'blog_post', :as => :blog_post
    JBUILDER

    assert_equal '[]', json
  end

  test 'render array if partials as a value' do
    json = render_jbuilder <<-JBUILDER
      json.posts BLOG_POST_COLLECTION, :partial => 'blog_post', :as => :blog_post
    JBUILDER

    assert_collection_rendered json, 'posts'
  end

  test 'render as empty array if partials as a nil value' do
    json = render_jbuilder <<-JBUILDER
      json.posts nil, :partial => 'blog_post', :as => :blog_post
    JBUILDER

    assert_equal '{"posts":[]}', json
  end

  test 'cache an empty block' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    render_jbuilder <<-JBUILDER
      json.cache! 'nothing' do
      end
    JBUILDER

    json = nil

    assert_nothing_raised do
      json = render_jbuilder <<-JBUILDER
        json.foo 'bar'
        json.cache! 'nothing' do
        end
      JBUILDER
    end

    assert_equal 'bar', MultiJson.load(json)['foo']
  end

  test 'fragment caching a JSON object' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.name 'Cache'
      end
    JBUILDER

    json = render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.name 'Miss'
      end
    JBUILDER

    parsed = MultiJson.load(json)
    assert_equal 'Cache', parsed['name']
  end

  test 'conditionally fragment caching a JSON object' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    render_jbuilder <<-JBUILDER
      json.cache_if! true, 'cachekey' do
        json.test1 'Cache'
      end
      json.cache_if! false, 'cachekey' do
        json.test2 'Cache'
      end
    JBUILDER

    json = render_jbuilder <<-JBUILDER
      json.cache_if! true, 'cachekey' do
        json.test1 'Miss'
      end
      json.cache_if! false, 'cachekey' do
        json.test2 'Miss'
      end
    JBUILDER

    parsed = MultiJson.load(json)
    assert_equal 'Cache', parsed['test1']
    assert_equal 'Miss', parsed['test2']
  end

  test 'fragment caching deserializes an array' do
    undef_context_methods :fragment_name_with_digest, :cache_fragment_name

    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.array! %w[a b c]
      end
    JBUILDER

    json = render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.array! %w[1 2 3]
      end
    JBUILDER

    parsed = MultiJson.load(json)
    assert_equal %w[a b c], parsed
  end

  test 'fragment caching works with previous version of cache digests' do
    undef_context_methods :cache_fragment_name

    @context.expects :fragment_name_with_digest

    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.name 'Cache'
      end
    JBUILDER
  end

  test 'fragment caching works with current cache digests' do
    undef_context_methods :fragment_name_with_digest

    @context.expects :cache_fragment_name
    ActiveSupport::Cache.expects :expand_cache_key

    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.name 'Cache'
      end
    JBUILDER
  end

  test 'current cache digest option accepts options' do
    undef_context_methods :fragment_name_with_digest

    @context.expects(:cache_fragment_name).with('cachekey', skip_digest: true)
    ActiveSupport::Cache.expects :expand_cache_key

    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey', skip_digest: true do
        json.name 'Cache'
      end
    JBUILDER
  end

  test 'does not perform caching when controller.perform_caching is false' do
    controller.perform_caching = false
    render_jbuilder <<-JBUILDER
      json.cache! 'cachekey' do
        json.name 'Cache'
      end
    JBUILDER

    assert_equal Rails.cache.inspect[/entries=(\d+)/, 1], '0'
  end

end
