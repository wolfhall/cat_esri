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
      crawler.guidify("da mittie").should == "916b09676ec55bde55d5416a2e8d15f48d8fc140"
    end

    it "guidify should produce a hexdigest normalized for slashes" do
      a = "c:\\fake_path"
      b = "c:/fake_path"
      crawler.guidify(a).should == crawler.guidify(b)
    end

    it "get_uniq_cloud should return a unique, non-numeric (except for uwi) string" do
      a = %w{ aaa <xml/> bbb a 1234567890 ccc RRR z12433`3`2"_)(*&^%$#@!""  FOO!!! }
      crawler.get_uniq_cloud(a).should == 'aaa xml bbb 1234567890 ccc RRR FOO'
    end

    it "deflate_encrypt and inflate_decrypt should hopefully work" do
      plain = File.join(@testdata, "plain.tmp")
      squish = File.join(@testdata, "squish.tmp")

      key = Digest::SHA1.hexdigest(ENV["PATH"])
      File.open(plain,'w'){|f| f << "I'm a SUPER cereal secret!"}
      xxx = crawler.deflate_encrypt(key, plain)
      File.open(squish,'w'){|f| f << xxx}
      crawler.inflate_decrypt(key,File.read(squish)).should == "I'm a SUPER cereal secret!"

      File.delete(plain) if File.exists?(plain)
      File.delete(squish) if File.exists?(squish)
    end


  end


end