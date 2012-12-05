require 'spec_helper'

module CatEsri

  #----------
  describe Publisher do

    # set gdal environment...
    ENV["GDAL_DATA"] = File.expand_path('../../../gdal/data',__FILE__)
    $LOAD_PATH.unshift File.expand_path('../../../gdal/apps',__FILE__)

    let(:output) { double('output').as_null_object }
    let(:crawler) { Crawler.new(output) }

    def get_tmps(type)
      Dir.glob("#{@testdata}/**/*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].{#{type}}")
    end

    def delete_tmps
      Dir.entries(@testdata).each do |f| 
	File.delete(File.join(@testdata,f)) if f.match(/\d{16}/)
      end
      Tire.index('test'){ delete }
    end

    before {
      @testdata = File.dirname(File.dirname(File.dirname(__FILE__)))+"/test"

      crawler.options = {
        :path => @testdata,
        :outdir => @testdata,
        :xitems => 1000,
	:max_features => 100,
        :group_name => 'test'
      }
      delete_tmps
    }

    after{
      delete_tmps
    }


    describe "#autoname" do

      #----------
      it "should correctly rename and timestamp a file by type" do
        opts = { :format => 'csv', :outdir => @testdata }
        Publisher.new(opts).autoname('map').should match(/MAP_\d{16}.csv/)
      end

    end


    describe "publish" do

      context "using csv output" do

	before{
	  crawler.options[:format] = 'csv'
	  crawler.options[:path] = @testdata
	  crawler.options[:xitems] = 8
	}

	#----------
	it "should write csv formatted file" do
	  crawler.scan
	  File.open(get_tmps('csv')[0]) {|f| f.readline}.should =~ /,+/
	end

	#----------
	it "should output more than one file if xitems is exceeded" do
	  crawler.scan
	  get_tmps('csv').size.should == 2
	end

	#----------
	it "should output the correct number of items across multiple files" do
	  crawler.scan
	  count = 0
	  get_tmps('csv').each do |p|
	    count += CSV.parse(File.read(p)).size
	  end
	  count.should == 11 # (2 header rows)
	end

	#----------
	it "should successfully append if xwrite is smaller than xitems" do
	  crawler.options[:xitems] = 100
	  crawler.options[:xwrite] = 1
	  crawler.scan
	  tmps = get_tmps('csv')
	  tmps.size.should == 1
	  CSV.parse(File.read(tmps[0])).size.should == 10
	end
	
	#----------
	it "should collect expected metadata" do
	  delete_tmps
	  crawler.options[:path] = File.join(@testdata,"AIRPORTS")
	  crawler.scan
	  tmps = get_tmps('csv')
	  tmps.size.should == 1
	  csv = CSV.parse(File.read(tmps[0]))
	  doc = Hash[csv[0].zip csv[1]]

	  doc["store"].should == "shapefile"
	  doc["identifier"].should == "airports"
	  doc["model"].should == "map"
	  doc["project"].should == "nonproj"
	  doc["checksum"].should == "b0c1a3bb92a255d5e57d8411022e697175c4f87f"
	  doc["bytes"].should == "31000"
	  doc["geometry"].should == "Point"
	  doc["native_extent"].should =~ /^(527953.500000, 4412454.114000)*/
	  doc["wkt"].should =~ /NAD_1983_UTM_Zone_13N/
	  doc["geojson"].should =~ /DenverZoo/

	end

      end


      context "using sqlite3 output" do

	before{
	  crawler.options[:format] = 'sqlite3'
	  crawler.options[:path] = @testdata
	  crawler.options[:xitems] = 8
	}
	
	#----------
	it "should write sqlite3 formatted file" do
	  crawler.scan
	  db = SQLite3::Database.new(get_tmps('sqlite3')[0])
	  table_names = db.execute("SELECT * FROM sqlite_master WHERE type='table';")
	  table_names.join(' ').to_s.should match(/maps/)
	  db.close
	end
	
	#----------
	it "should output more than one file if xitems is exceeded" do
	  crawler.scan
	  get_tmps('sqlite3').size.should == 2
	end

	#----------
	it "should write the correct number of items across multiple files" do
	  crawler.scan
	  count = 0
	  get_tmps('sqlite3').each do |p|
	    db = SQLite3::Database.new(p)
	    count += db.execute("select count(*) from maps;")[0][0]
	    db.close
	  end
	  count.should == 9
	end

	#----------
	it "should successfully append if xwrite is smaller than xitems" do
	  crawler.options[:xitems] = 100
	  crawler.options[:xwrite] = 1
	  crawler.scan
	  tmps = get_tmps('sqlite3')
	  tmps.size.should == 1
	  db = SQLite3::Database.new(tmps[0])
	  db.execute("select count(*) from maps;")[0][0].should == 9
	  db.close
	end

	#----------
	it "should collect expected metadata" do
	  delete_tmps
	  crawler.options[:path] = File.join(@testdata,"AIRPORTS")
	  crawler.scan
	  tmps = get_tmps('sqlite3')
	  tmps.size.should == 1
	  db = SQLite3::Database.new(tmps[0])
	  doc = db.execute("select store, identifier, model, project, checksum, bytes, geometry, native_extent, wkt, geojson from maps;")[0]
	  db.close

	  doc[0].should == "shapefile"
	  doc[1].should == "airports"
	  doc[2].should == "map"
	  doc[3].should == "nonproj"
	  doc[4].should == "b0c1a3bb92a255d5e57d8411022e697175c4f87f"
	  doc[5].should == 31000
	  doc[6].should == "Point"
	  doc[7].should =~ /^(527953.500000, 4412454.114000)*/
	  doc[8].should =~ /NAD_1983_UTM_Zone_13N/
	  doc[9].should =~ /DenverZoo/

	end

      end


      context "using elasticsearch output" do

	before{
	  crawler.options[:format] = 'elasticsearch'
	  crawler.options[:elastic_url] = 'http://localhost:9200/test'
	}

	#----------
	it "should write to and read from local elasticsearch index" do

	  Tire.index('test'){ create }
	  crawler.scan

	  s = Tire.search('test') do
	    query { string "map" }
	    highlight "cloud"
	  end

	  s.results.size.should == 9

	  s = Tire.search('test') do
	    query { string "DenverZoo" }
	    highlight "cloud"
	  end

	  s.results.size.should == 1

	  s.results.first.highlight[:cloud].join.should =~ /<em>DenverZoo/

	end

	#----------
	it "should collect expected metadata" do
	  delete_tmps
	  crawler.options[:path] = File.join(@testdata,"AIRPORTS")
	  Tire.index('test'){ create }
	  crawler.scan

	  s = Tire.search('test') do
	    query { string "DenverZoo" }
	  end

	  s.results.size.should == 1

	  doc = s.results.first.to_hash
	  
	  doc[:store].should == "shapefile"
	  doc[:identifier].should == "airports"
	  doc[:model].should == "map"
	  doc[:project].should == "nonproj"
	  doc[:checksum].should == "b0c1a3bb92a255d5e57d8411022e697175c4f87f"
	  doc[:bytes].should == 31000
	  doc[:geometry].should == "Point"
	  doc[:native_extent].should =~ /^(527953.500000, 4412454.114000)*/
	  doc[:wkt].should =~ /NAD_1983_UTM_Zone_13N/
	  doc[:geojson].should =~ /DenverZoo/
	  
	end

      end
      

      context "using cloud output" do

	#----------
	it "should upload an encrypted csv file to amazon" do
	  pending "TODO get mock-aws-s3 working on windows?"
	  crawler.options[:format] = 'cloud'
	  crawler.scan
	end

      end



    end
    

  end

end















=begin
    describe "#publish" do

      it "should output more than one file if xitems is exceeded" do
        crawler.options[:path] = @testdata
        crawler.options[:ggxlayer] = true
        crawler.options[:xitems] = 5
        crawler.options[:format] = 'csv'
        crawler.scan
        get_tmps('csv').size.should == 2
      end

      it "should write the correct number of items when writing to multiple files" do
        crawler.options[:path] = @testdata
        crawler.options[:ggxlayer] = true
        crawler.options[:xitems] = 5
        crawler.options[:format] = 'sqlite3'
        crawler.scan
        count = 0
        get_tmps('sqlite3').each do |p|
          db = SQLite3::Database.new(p)
          count += db.execute("select count(*) from maps;")[0][0]
          db.close
        end
        count.should == 9
      end

      it "should write sqlite3 formatted file" do
        crawler.options[:format] = 'sqlite3'
        crawler.scan
        db = SQLite3::Database.new(get_tmps('sqlite3')[0])
        table_names = db.execute("SELECT * FROM sqlite_master WHERE type='table';")
        table_names.join(' ').to_s.should match(/maps/)
        db.close
      end

      it "should write csv formatted file" do
        crawler.options[:format] = 'csv'
        crawler.scan
        File.open(get_tmps('csv')[0]) {|f| f.readline}.should =~ /,+/
      end

      it "should write to an elasticsearch index" do

        #assumes you have elasticsearch running locally
        crawler.options[:format] = 'elasticsearch'
        crawler.options[:elastic_url] = 'http://localhost:9200/test'
        Tire.index('test'){ create }
        crawler.scan

        s = Tire.search('test') do
          query { string "runways" }
          highlight "cloud"
        end

        s.results.size.should == 1
        s.results.first.highlight[:cloud].join.should =~ /<em>RUNWAYS/

        Tire.index('test'){ delete }
      end


    end
  end

end
=end
