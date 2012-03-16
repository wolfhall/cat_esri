require 'spec_helper'

module CatEsri

  #----------
  describe "lc_util" do
    let(:output) { double('output').as_null_object }
    let(:crawler) { Crawler.new(output) }
    before{
      @testdata = File.dirname(File.dirname(File.dirname(__FILE__)))+"/data"
    }

    it "mince should parse a string ridiculously" do
      crawler.mince("\\\\server\\share\\a_b_c_a~l!p@h#a$b%e^t&s*o(u)p.xyz-hij@foo+bar").should ==
      "server share a b c al p h a b e t s o u p xyz hij foo bar"
    end

    it "checksum should correctly generate a checksum" do
      @rasfile = File.join(@testdata,'test.mdb')
      crawler.checksum(@rasfile).should == "233f1681efbf01704671823a14bfed25"
    end

    it "checksum should skip a directory" do
      crawler.checksum(@testdata).should == nil
    end

    it "hostname should return something" do
      crawler.hostname.should_not == nil
    end

    it "guidify should guidify a string" do
      crawler.guidify("da mittie").should == "376b47f147ee4e597d7527f8701ce56c"
    end

    it "get_uniq_cloud should return a unique, non-numeric (except for uwi) string" do
      a = %w{ aaa <xml/> bbb a 1234567890 ccc RRR z12433`3`2"_)(*&^%$#@!""  FOO!!! }
      crawler.get_uniq_cloud(a).should == 'aaa xml bbb 1234567890 ccc RRR FOO'
    end

  end

  describe "Crypto" do
    before{
      @file = File.dirname(File.dirname(File.dirname(__FILE__)))+"/data/bogus.txt"
      @zipfile = File.dirname(File.dirname(File.dirname(__FILE__)))+"/data/bogus.zip"
      @cryptokey = "fake_key"
      @crypt = Crypto.new(@cryptokey)
      @crypt.write_cryptozip_file(@file)
    }

    it "should zip and encrypt a file" do
      File.exists?(@zipfile).should be true
      @crypt.data.should match(/^bogus/)
      @crypt.encrypted_data.length.should > 0
    end

    it "should decrypt a zipped file" do
      @crypt.read_cryptozip_file(@zipfile)
      @crypt.data.should match(/^bogus/)
    end

    # not releasing filehandle in time. just leave it.
    #after{
    #  File.delete(@zipfile) if File.exists?(@zipfile)
    #}

  end






end