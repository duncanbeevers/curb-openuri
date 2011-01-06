require File.dirname(__FILE__) + '/spec_helper'

describe "CurlAgent" do

  describe 'new method' do
    it 'shall permit to override user-agent later' do
      curl = CurlAgent.new('http://www.example.com/')
      curl.headers['User-Agent'].should_not be_nil
      curl.headers['User-Agent'] = 'curl'
      curl.headers['User-Agent'].should == 'curl'
    end
  end

  describe 'when used alone' do
    before(:each) do
      @mock = mock('curl_easy')
      @headers = {'User-Agent' => 'foo'}
      @mock.stub!(:headers).and_return(@headers)
      @mock.stub!(:'follow_location=')
      @mock.stub!(:'max_redirects=')
      @mock.stub!(:'enable_cookies=')
      @mock.stub!(:'connect_timeout=')
      @mock.stub!(:'timeout=')
      @mock.should_receive(:perform)
      Curl::Easy.should_receive(:new).and_return(@mock)
    end

    it 'should recognize charset' do
      @mock.stub!(:content_type).and_return('Content-Type: text/html;charset=utf-8')
      curl = CurlAgent.new('http://www.example.com/')
      curl.charset.should == 'utf-8'
    end

    it 'should recognize upper case charset' do
      @mock.stub!(:content_type).and_return('Content-Type: text/html;charset=Windows-1251')
      curl = CurlAgent.new('http://www.example.com/')
      curl.charset.should == 'windows-1251'
    end

    it 'should return empty str for empty charset' do
      @mock.stub!(:content_type).and_return('Content-Type: text/html')
      @mock.should_receive(:body_str).once
      curl = CurlAgent.new('http://www.example.com/')
      curl.charset.should == ''
    end

    it 'should attempt to find charset in html' do
      @mock.stub!(:content_type).and_return('Content-Type: text/html')
      @mock.stub!(:body_str).and_return(<<EOF)
      <html>
      <head>
      <meta content="text/html; charset=ISO-8859-1" http-equiv="Content-Type"/>
      </head>
      <body></body>
      </html>
EOF
      curl = CurlAgent.new('http://www.example.com/')
      curl.charset.should == 'iso-8859-1'
    end
  end

  describe 'when used with open' do
    before(:each) do
      @headers = {'User-Agent'=>'foo'}
      @url = 'http://www.example.com/'
      @curl_easy = mock('curl_easy')
      Curl::Easy.should_receive(:new).and_return(@curl_easy)
      @curl_easy.stub!(:headers).and_return(@headers)
      @curl_easy.stub!(:follow_location=)
      @curl_easy.stub!(:max_redirects=)
      @curl_easy.stub!(:enable_cookies=)
      @curl_easy.stub!(:connect_timeout=)
      @curl_easy.stub!(:timeout=)
      @curl_easy.stub!(:perform)
      @curl_easy.stub!(:body_str).and_return('test')
      @curl_easy.stub!(:response_code).and_return(200)
      @curl_easy.stub!(:last_effective_url).and_return(@url)
      @curl_easy.stub!(:header_str).and_return("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nServer: Apache")
    end

    it 'shall permit to specify user-agent' do
      @curl_easy.headers['User-Agent'].should_not == 'curl'
      CurlAgent.open(@url, 'User-Agent'=>'curl')
      @curl_easy.headers['User-Agent'].should == 'curl'
    end

    it 'shall permit to override timeout' do
      @curl_easy.should_receive(:'timeout=').once.with(10)
      CurlAgent.open(@url, :timeout => 10)
    end

    describe 'with OpenURI::OpenRead option' do
      describe ':proxy' do
        it 'shall set :proxy_url' do
          proxy_url = 'http://proxy.example.com:8000'
          @curl_easy.should_receive(:'proxy_url=').once.with(proxy_url)
          CurlAgent.open(@url, :proxy => proxy_url)
        end
      end

      describe ':proxy_http_basic_authentication' do
        it 'shall set :proxypwd' do
          proxypwd = 'example_username:secret'
          @curl_easy.should_receive(:'proxypwd=').once.with(proxypwd)
          CurlAgent.open(@url, :proxy_http_basic_authentication => proxypwd)
        end
      end

      describe ':http_basic_authentication' do
        it 'shall set :userpwd' do
          userpwd = 'example_username:secret'
          @curl_easy.should_receive(:'userpwd=').once.with(userpwd)
          CurlAgent.open(@url, :http_basic_authentication => userpwd)
        end
      end

      describe ':content_length_proc' do
        it 'shall be invoked with the content length' do
          threaded_on_progress = nil
          @curl_easy.should_receive(:downloaded_content_length).and_return(10)
          @curl_easy.should_receive(:'on_progress=').once.with do |on_progress|
            threaded_on_progress = on_progress
            true
          end
          cl_proc = mock('content_length_proc')
          cl_proc.should_receive(:call).with(10)

          CurlAgent.open(@url, :content_length_proc => cl_proc)
          threaded_on_progress.call(nil, nil, nil, nil)
          threaded_on_progress.call(nil, nil, nil, nil)
        end

        it 'shall not be invoked if downloaded_content_length is not available' do
          threaded_on_progress = nil
          @curl_easy.should_receive(:downloaded_content_length).
            at_least(1).and_return(nil)
 
          @curl_easy.should_receive(:'on_progress=').once.with do |on_progress|
            threaded_on_progress = on_progress
            true
          end

          CurlAgent.open(@url, :content_length_proc => mock('content_length_proc'))
          threaded_on_progress.call(nil, nil, nil, nil)
          threaded_on_progress.call(nil, nil, nil, nil)
        end
      end

      describe ':progress_proc' do
        it 'shall be invoked with current progress' do
          threaded_on_progress = nil
          @curl_easy.stub!(:downloaded_content_length)
          @curl_easy.should_receive(:'on_progress=').once.with do |on_progress|
            threaded_on_progress = on_progress
            true
          end
          pg_proc = mock('progress_proc')
          pg_proc.should_receive(:call).with(2).ordered
          pg_proc.should_receive(:call).with(3).ordered

          CurlAgent.open(@url, :progress_proc => pg_proc)
          threaded_on_progress.call(nil, 2, nil, nil)
          threaded_on_progress.call(nil, 3, nil, nil)
        end
      end

      describe ':read_timeout' do
        it 'shall set :timeout' do
          @curl_easy.should_receive(:'timeout=').once.with(10)
          CurlAgent.open(@url, :read_timeout => 10)
        end
      end

      describe ':ssl_ca_cert' do
        it 'shall set :cacert' do
          ca_cert = "Certificate Authority Certificate"
          @curl_easy.should_receive(:'cacert=').once.with(ca_cert)
          CurlAgent.open(@url, :ssl_ca_cert => ca_cert)
        end
      end

      describe ':ssl_verify_mode' do
        it 'shall set :ssl_verify_host' do
          verify_mode = 1 # OpenSSL::SSL::VERIFY_PEER
          @curl_easy.should_receive(:'ssl_verify_host=').once.with(true)
          CurlAgent.open(@url, :ssl_verify_mode => verify_mode)
        end
      end

      describe ':ftp_active_mode' do
        it 'shall not be sent to curlagent' do
          @curl_easy.should_not_receive(:'ftp_active_mode')
          CurlAgent.open(@url, :ftp_active_mode => 'discard')
        end
      end

      describe ':redirect' do
        it 'shall set :follow_location' do
          @curl_easy.should_receive(:'follow_location=').once.with(true)
          CurlAgent.open(@url, :redirect => true)
        end
      end

    end

    it 'shall use block when provided' do
      CurlAgent.open(@url) {|f| f.read}.should == 'test'
    end

    it 'shall return io object which responds to base_uri' do
      io = CurlAgent.open(@url)
      io.should respond_to(:base_uri)
      io.base_uri.should be_a_kind_of(URI)
      io.base_uri.to_s.should == @url
    end

    it 'shall return io object which responds to meta' do
      io = CurlAgent.open(@url)
      io.should respond_to(:meta)
      meta = io.meta
      meta.should be_a_kind_of(Hash)
      meta.should have(2).keys
      meta['server'].should == 'Apache'
    end
  end

  describe 'when parsing parameters to open' do
    it 'shall recognize wrong mode' do
      CurlAgent.should_not_receive(:new)
      lambda {CurlAgent.open('http://www.example.com/', 'w', 0600, :timeout=>10)}.should raise_error(ArgumentError)
    end
  end
end
