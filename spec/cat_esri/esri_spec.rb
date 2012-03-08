require 'spec_helper'

module CatEsri

  #----------
  describe Crawler do
    let(:output) { double('output').as_null_object }
    let(:crawler) { Crawler.new(output) }

    def get_tmps(type)
      Dir.glob("#{@testdata}/**/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].{#{type}}")
    end

    before {
      @testdata = File.dirname(File.dirname(File.dirname(__FILE__)))+"/data"
      crawler.options = {
        :path => @testdata,
        :outdir => @testdata,
        :xitems => 50000
      }
    }

    after{
      Dir.entries(@testdata).each { |f|  File.delete(File.join(@testdata,f)) if f.match(/MAP_\d{16}/) }
    }

    #----------
    describe "#find_esri" do

      it "should ignore an empty directory" do
        crawler.options[:path] = File.join(@testdata,'empty')
        crawler.should_not_receive(:parse_shp)
        crawler.scan
      end

      it "should find shapefiles" do
        crawler.options[:path] = @testdata
        output.should_receive(:puts).with(/^Processing ESRI Shapefile:/).once
        crawler.scan
      end

      it "should find file geodatabases" do
        crawler.options[:path] = @testdata
        crawler.options[:esrigdb] = true
        output.should_receive(:puts).with(/^Processing ESRI File Geodatabase:/).once
        crawler.scan
      end

      it "should find personal geodatabases if on Windows" do
        if crawler.os == "mingw32"
          crawler.options[:path] = @testdata
          crawler.options[:esrigdb] = true
          output.should_receive(:puts).with(/^Processing ESRI Personal Geodatabase:/).once
          crawler.scan
        else
          crawler.should_not_receive(:parse_pgdb)
        end
      end

    end

    #----------
    describe "#prune" do

      it "should exclude --quell (prune) dirs" do
        crawler.options[:path] = @testdata
        crawler.options[:quell] = File.join(@testdata,'ggx_layer')
        crawler.prune?(File.join(@testdata,'ggx_layer')).should == true
      end

      it "should exclude non-matching dirs" do
        crawler.options[:path] = @testdata
        crawler.options[:quell] = File.join(@testdata,'ggx_layer')
        crawler.prune?(File.join(@testdata,'bogus')).should == false
      end

    end

    #----------
    describe "#parse_shp" do

      it "should parse and output metadata on a valid shapefile" do
        crawler.options[:path] = File.join(@testdata,'AIRPORTS/AIRPORTS.shp')
        crawler.options[:format] = 'csv'
        output.should_receive(:puts).with(/^Processing ESRI Shapefile:/).once
        crawler.scan
        File.exist?(get_tmps('csv')[0]).should == true
      end

      it "should not parse a geoatlas layer without ggxlayer flag" do
        crawler.options[:path] = File.join(@testdata,'ggx_layer')
        output.should_not_receive(:puts).with(/^Processing ESRI Shapefile:/)
        crawler.scan
      end

      it "should parse a geoatlas layer with ggxlayer flag" do
        crawler.options[:path] = File.join(@testdata,'ggx_layer')
        crawler.options[:ggxlayer] = true
        output.should_receive(:puts).with(/^Processing ESRI Shapefile:/).exactly(8).times
        crawler.scan
      end

      it "should warn if path is invalid" do
        crawler.options[:path] = File.join(@testdata,'bogus.txt')
        output.should_receive(:puts).with(/^Invalid crawler path/)
        crawler.scan
      end

      # impractical to include a huge shapefile in the gem, but here's the timeout test
      it "should timeout on huge shapefiles" do
        pending "needs a big file to test with"
        crawler.options[:path] = '/Users/rbh/Documents/bucket/test_data_broken/big_shp/W_WELL NAME-ALL/0-402-Posted Text.shp'
        crawler.options[:timeout] = 1
        output.should_receive(:puts).with(/Exceeded timeout limit/)
        crawler.scan
      end

    end


    #----------
    describe "#parse_pgdb" do
      if RbConfig::CONFIG['target_os'] == "mingw32"

        it "should not parse a personal geodatabase if the esrigdb flag is false" do
          crawler.options[:path] = File.join(@testdata)
          crawler.options[:esrigdb] = false
          output.should_not_receive(:puts).with(/^Processing ESRI Personal Geodatabase:/)
          crawler.scan
        end

        it "should parse a personal geodatabase if the esrigdb flag is true" do
          crawler.options[:path] = File.join(@testdata,'test.mdb')
          crawler.options[:format] = 'csv'
          crawler.options[:esrigdb] = true
          output.should_receive(:puts).with(/^Processing ESRI Personal Geodatabase:/).once
          crawler.scan
          File.exist?(get_tmps('csv')[0]).should == true
        end

        # impractical to include a huge geodb in the gem, but here's the timeout test
        it "should timeout on huge personal geodatabase" do
          pending "needs a big file to test with"
          crawler.options[:path] = 'data/test.mdb'
          crawler.options[:timeout] = 1
          output.should_receive(:puts).with(/Exceeded timeout limit/)
          crawler.scan
        end

      end
    end


    #----------
    describe "#parse_fgdb" do

      it "should parse and output metadata on a valid file geodatabase" do
        crawler.options[:path] = File.join(@testdata,'mygdb.gdb')
        crawler.options[:format] = 'csv'
        output.should_receive(:puts).with(/^Processing ESRI File Geodatabase:/).once
        crawler.scan
        File.exist?(get_tmps('csv')[0]).should == true
      end

      it "should not parse a file geodatabase if the esrigdb flag is false" do
        crawler.options[:path] = File.join(@testdata,'mygdb.gdb')
        crawler.options[:esrigdb] = false
        output.should_not_receive(:puts).with(/^Processing ESRI File Geodatabase:/).once
        crawler.scan
      end

      # impractical to include a huge geodb in the gem, but here's the timeout test
      it "should timeout on huge file geodatabase" do
        pending "needs big file to test with"
        crawler.options[:path] = '/Users/rbh/Documents/bucket/test_data/gis/Allpoints_Petro/TeapotDome.gdb'
        crawler.options[:timeout] = 1
        output.should_receive(:puts).with(/Exceeded timeout limit/)
        crawler.scan
      end

    end


    #----------
    describe "esri helper methods" do
      before{
        @shp = File.join(@testdata,'/AIRPORTS/AIRPORTS.shp')
      }

      it "norm_spatialref should tease out coordinate system from messy string" do
        line = <<-END
        PROJCS["NAD_1983_UTM_Zone_13N",GEOGCS["GCS_North_American_1983",DATUM["D_North_American_1983",
          SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT
          ["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER
          ["False_Easting",500000.0],PARAMETER["False_Northing",0.0],PARAMETER
          ["Central_Meridian",-105.0],PARAMETER["Scale_Factor",0.9996],PARAMETER
          ["Latitude_Of_Origin",0.0],UNIT["Meter",1.0]]
        END
        crawler.norm_spatialref(line).length.should == 454
      end

      #basically the same thing...
      it "get_shp_coordsys should extract shapefile projection" do
        crawler.get_shp_coordsys(@shp).length.should == 399
      end

      it "get_dbf_cloud should extract cloud from shapefile .dbf" do
        crawler.get_dbf_cloud(@shp).size.should == 391
      end

      it "get_multi_shp_checksum should return a composite checksum from all shp files" do
        crawler.get_multi_shp_checksum(@shp).should == '06ce3c5e7b03e736ee81ebd37cd932b4'
      end

      it "get_multi_shp_bytes should return sum from all shp files" do
        crawler.get_multi_shp_bytes(@shp).should == 31000
      end

      it "get_fgdb_checksum should return composite checksum from fgdb" do
        fgdb = File.join(@testdata,'mygdb.gdb')
        crawler.get_fgdb_checksum(fgdb).should == '95be2b113a56481a2b55959c1fc9a5b6'
      end

    end

  end

end