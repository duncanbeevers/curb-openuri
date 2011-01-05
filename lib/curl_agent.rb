require 'rubygems'
require 'stringio'
require 'curb'
require 'uri'

class CurlAgent
  OPEN_URI_OPEN_OPTIONS = [
    :proxy, :proxy_http_basic_authentication, :http_basic_authentication,
    :content_length_proc, :progress_proc,
    :read_timeout,
    :ssl_ca_cert, :ssl_verify_mode,
    :ftp_active_mode,
    :redirect ]

  # See CurlAgent::open for explanation about options
  def initialize(url, options = {})
    @curl = Curl::Easy.new(url)
    # Defaults
    @curl.headers['User-Agent'] = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.6) Gecko/2009011913 Firefox/3.0.6'
    @curl.follow_location = true
    @curl.max_redirects = 2
    @curl.enable_cookies = true
    @curl.connect_timeout = 5
    @curl.timeout = 30
    @performed = false

    # Duplicate the functionality of the OpenURI open options
    # by transforming options into Curl::Easy configuration directives
    headers = {}
    curl_config = {}
    
    if options
      curl_config[:proxy_url] = options[:proxy].to_s if options[:proxy]
      curl_config[:proxypwd] = options[:proxy_http_basic_authentication].to_s if options[:proxy_http_basic_authentication]
      curl_config[:userpwd] = options[:http_basic_authentication].to_s if options[:http_basic_authentication]
      if options[:content_length_proc] || options[:progress_proc]
        on_content_length = options[:content_length_proc]
        on_progress = options[:progress_proc]

        curl_config[:on_progress] = lambda { |dl_total, dl_now, ul_total, ul_now|
          # on_content_length, if it was defined, is a one-shot
          if on_content_length && self.downloaded_content_length
            on_content_length.call(self.downloaded_content_length)
            on_content_length = nil
          end
          
          on_progress.call(dl_now) if on_progress
        }
      end
      curl_config[:timeout] = options[:read_timeout] if options[:read_timeout]

      # These SSL configs are untested, just skethed in
      curl_config[:cacert] = options[:ssl_ca_cert].to_s if options[:ssl_ca_cert]
      curl_config[:ssl_verify_host] = options[:ssl_verify_mode] if options[:ssl_verify_mode]
      curl_config[:follow_location] = true if options[:redirect]

      # I didn't see any support in Curl::Easy for specifying FTP active/passive
      # so :ftp_active_mode is just discarded

      # Remove any OpenURI open options from the Curl::Easy configuration
      OPEN_URI_OPEN_OPTIONS.each { |(k, _)| options.delete(k) }

      (options || {}).each do |k, v|
        # Strings will be passed as headers, as in original open-uri
        (k.is_a?(Symbol) ? curl_config : headers)[k] = v
      end
    end

    # Configure curl
    curl_config.each do |k, v|
      @curl.send("#{k}=".intern, v)
    end

    # All that's left should be considered headers
    @curl.headers.merge!(headers)
  end

  # Do the actual fetch, after which it's possible to call body_str method
  def perform!
    @curl.perform
    @performed = true
  end

  # Returns the charset of the page
  def charset
    perform! unless @performed
    content_type = @curl.content_type || ''
    charset = if content_type.match(/charset\s*=\s*([a-zA-Z0-9-]+)/ni)
        $1
      elsif ! body_str.nil? and (m = body_str.slice(0,1000).match(%r{<meta.*http-equiv\s*=\s*['"]?Content-Type['"]?.*?>}mi)) and
        m[0].match(%r{content=['"]text/html.*?charset=(.*?)['"]}mi)
        $1
      else
        ''
      end.downcase
  end

  # Proxies all calls to Curl::Easy instance
  def respond_to?(symbol)
    @curl.respond_to?(symbol)
  end

  # Proxies all calls to Curl::Easy instance
  def method_missing(symbol, *args)
    @curl.send(symbol, *args)
  end

  # This method opens the URL and returns an IO object.
  # If a block is provided, it's called with that object.
  # You can override defaults and provide configuration directives
  # to Curl::Easy with symbol hash keys, for example:
  # open('http://www.example.com/', :timeout => 10)
  # all the rest keys will be passed as headers, for example:
  # open('http://www.example.com/', :timeout => 10, 'User-Agent'=>'curl')
  def self.open(name, *rest, &block)
    mode, perm, rest = scan_open_optional_arguments(*rest)
    options = rest.shift if !rest.empty? && Hash === rest.first
    raise ArgumentError.new("extra arguments") if !rest.empty?

    unless mode == nil || mode == 'r' || mode == 'rb' || mode == File::RDONLY
      raise ArgumentError.new("invalid access mode #{mode} (resource is read only.)")
    end

    agent = CurlAgent.new(name, options)

    agent.perform!
    io = IO.new(agent.body_str, agent.header_str)
    io.base_uri = URI.parse(agent.last_effective_url) rescue nil
    io.status = [agent.response_code, '']
    if block
      block.call(io)
    else
      io
    end
  end

  def self.scan_open_optional_arguments(*rest) # :nodoc:
    if !rest.empty? && (String === rest.first || Integer === rest.first)
      mode = rest.shift
      if !rest.empty? && Integer === rest.first
        perm = rest.shift
      end
    end
    return mode, perm, rest
  end

  class IO < StringIO
    # returns an Array which consists status code and message.
    attr_accessor :status

    # returns a URI which is base of relative URIs in the data.
    # It may differ from the URI supplied by a user because redirection.
    attr_accessor :base_uri

    def initialize(body_str, header_str)
      super(body_str)
      @header_str = header_str
    end

    # returns a Hash which represents header fields.
    # The Hash keys are downcased for canonicalization.
    def meta
      @meta ||= begin
        arr = @header_str.split(/\r?\n/)
        arr.shift
        arr.inject({}) do |hash, hdr|
          key, val = hdr.split(/:\s+/, 2)
          hash[key.downcase] = val
          hash
        end
      end
    end
  end
end
