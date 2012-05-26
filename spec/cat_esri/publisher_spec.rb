require 'spec_helper'

module CatEsri

  #----------
  describe Publisher do

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
    describe "#autoname" do

      it "should correctly rename and timestamp a file by type" do
        opts = { :format => 'csv', :outdir => @testdata }
        Publisher.new(opts).autoname('map').should match(/MAP_\d{16}.csv/)
      end

    end


    #----------
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
