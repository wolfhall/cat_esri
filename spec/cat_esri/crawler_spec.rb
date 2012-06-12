require 'spec_helper'

module CatEsri

  #----------
  describe Crawler do
    let(:output) { double('output').as_null_object }
    let(:crawler) { Crawler.new(output) }

    before {
      @testdata = File.dirname(File.dirname(File.dirname(__FILE__)))+"/data"
      opts = {
        :outdir => @testdata,
        :path=>"data/AIRPORTS/AIRPORTS.shp",
        :format=>"csv",
        :timeout=>30,
        :xitems=>50000,
        :group_name => 'test'
        }
      crawler.options = opts
    }

    after{
      File.delete(File.join(@testdata,'tmp.log')) if File.exist?(File.join(@testdata,'tmp.log'))
    }

    #----------
    describe "#initialize" do

      it "queries the OS" do
        crawler.os.should_not == nil
      end

      it "sends a welcome message" do
        output.should_receive(:puts).with('----- LogicalCat ESRI Crawler -----')
        crawler.scan
      end

    end


    #----------
    # trollop will have filtered out the following conditions:
    # no args, blank path, nonexistent path, unknown format, invalid outfile
    # directories and parsing errors like half-quoted strings
    describe "#scan" do
      it "parses a shapefile if path ends with .shp" do
        crawler.options[:path] = File.join(@testdata,'AIRPORTS/AIRPORTS.shp')
        crawler.should_receive(:parse_shp).once
        crawler.scan
      end

      it "parses a personal geodatabase if path ends with .mdb and --esrigdb is true on Windows" do
        if crawler.os == "mingw32"
          crawler.options[:path] = File.join(@testdata,'test.mdb')
          crawler.options[:esrigdb] = true
          crawler.should_receive(:parse_pgdb).once
          crawler.scan
        else
          crawler.options[:path] = File.join(@testdata,'test.mdb')
          crawler.options[:esrigdb] = true
          output.should_receive(:puts).with(/^Sorry, ESRI Personal Geodatabase scan only works on Windows./)
          crawler.scan
        end
      end

      it "parses a file geodatabase if path is a gdb folder and --esrigdb is true" do
        crawler.options[:path] = File.join(@testdata,'mygdb.gdb')
        crawler.options[:esrigdb] = true
        crawler.should_receive(:parse_fgdb).once
        crawler.scan
      end

      it "complains about a non-esri file path" do
        crawler.options[:path] = File.join(@testdata,'bogus.txt')
        crawler.options[:esrigdb] = true
        output.should_receive(:puts).with(/^Invalid crawler path:/)
        crawler.scan
      end

      it "ignores an empty directory" do
        crawler.options[:path] = File.join(@testdata,'empty')
        crawler.should_not_receive(:parse_shp)
        crawler.should_not_receive(:parse_pgdb)
        crawler.should_not_receive(:parse_fgdb)
        crawler.scan
      end

      it "ignores a geographix layer if ggxlayer is false" do
        crawler.options[:path] = File.join(@testdata,'ggx_layer')
        crawler.should_not_receive(:parse_shp)
        crawler.scan
      end

      it "finds shapefiles, geodatabases including ggx layers if flagged" do
        crawler.options[:path] = File.join(@testdata)
        crawler.options[:esrigdb] = true
        crawler.options[:ggxlayer] = true
        crawler.should_receive(:parse_shp).exactly(9).times
        crawler.should_receive(:parse_fgdb).once
        crawler.scan
      end

    end


    #----------
    describe "logger" do
      it "should log crawl activity" do
        crawler.options[:logfile] = File.join(@testdata,'tmp.log')
        crawler.scan
        File.exist?(File.join(@testdata,'tmp.log')).should == true
      end
    end


  end

end
