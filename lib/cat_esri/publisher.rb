module CatEsri

  FORMATS = %w(sqlite3 csv search_index)

  class Publisher
    include CatEsri

    #----------
    def initialize(options)
      @vault = []
      @output = options[:output]
      @outdir = options[:outdir]
      @xitems = options[:xitems]
      @format = options[:format]
      @logger = options[:logger]

      @ini_cipher = options[:ini_cipher]
      @ini_path = options[:ini_path]
      @keep_tmps = options[:keep_tmps]
    end


    #----------
    # add a map hash to the vault, publish if xitems
    def add_map(x)
      @vault << x
      if @vault.size == @xitems
        publish(autoname('map'),'maps')
        @vault.clear
      end
    end


    #----------
    # Publish any remaining data (i.e. haven't exceeded xitems) from various arrays.
    def wrap_it_up
      publish(autoname('map'),'maps') if @vault.size > 0
    end


    #----------
    # Ensure unique file names by using datatype, timestamp (with microseconds) and suffix.
    # Also gets called when xitems limit is reached.
    def autoname(type)
      return unless @outdir
      stamp = sprintf('%.6f',"#{Time.now.to_i}.#{Time.now.usec}".to_f).gsub('.','')
      File.join(@outdir,"#{type.upcase}_#{stamp}.#{@format.downcase}")
    end


    #----------
    # Write .csv or sqlite3 files. Assume everything went okay if outfile exists.
    def publish(outfile,table_name)

      @output.puts "\nWriting #{@vault.size} #{@format} entries..."
      @logger.info "Writing #{@vault.size} #{@format} entries..." if @logger

      case @format
      when 'sqlite3'

        @output.puts "Writing to: #{outfile}"
        @logger.info "Writing to: #{outfile}" if @logger

        begin
          db = SQLite3::Database.new(outfile)
          db.execute("create table #{table_name} (#{@vault[0].keys.collect{|x| x.to_s}.join(',')})")
          db.execute("begin transaction")
          @vault.each do |r|
            s = "insert into #{table_name} (#{r.keys.collect{|x|x.to_s}.join(',')}) values (#{r.values.collect{|x| "'#{x}'"}.join(',')})"
            db.execute(s)
          end
          db.execute("commit")
          db.close
        rescue Exception => e
          raise e
        end

      when 'csv'

        @output.puts "Writing to: #{outfile}"
        @logger.info "Writing to: #{outfile}" if @logger

        CSV.open(outfile, "wb") do |csv|
          csv << @vault[0].keys.to_a
          @vault.each do |r|
            begin
              csv << r.values.to_a
            rescue Exception => e
              @output.puts "csv parsing error: #{e}"
              @logger.info "csv parsing error: #{e}" if @logger
            end
          end
        end

      when 'search_index'

        unless File.exists?(@ini_path)
          @output.puts "Aborting upload, storage ini not found: #{@ini_path}"
          @logger.error "Aborting upload, storage ini not found: #{@ini_path}" if @logger
          return
        end

        ini = decrypted_inflated_ini(@ini_cipher, @ini_path)

        #ini['local_index'] = 'logicalcat_index'

        if ini['local_index'].nil?

          searchify_url = ini['searchify_url']
          searchify_idx = ini['searchify_idx']

          api = IndexTank::Client.new searchify_url
          idx = api.indexes searchify_idx

          documents = []
          @vault.each do |fields|
            documents << {:docid => fields[:guid], :fields => fields }
          end

          @output.puts "Batch inserting Searchify documents...\n\n"
          @logger.info "Batch inserting Searchify documents..." if @logger
          response = idx.batch_insert(documents)

          response.each_with_index do |r, i|
            unless r['added']
              @output.puts "Searchify upload error: #{r}"
              @logger.error "Searchify upload error: #{r}" if @logger
            end
          end

        else

          idx = ini['local_index']

          documents = []
          @vault.each do |fields|
            documents << fields.merge({:id => fields[:guid]})
          end

          @output.puts "Batch inserting ElasticSearch documents...\n\n"
          @logger.info "Batch inserting ElasticSearch documents..." if @logger
          begin
            Tire.index idx do
              import documents
              refresh
            end
          rescue Exception => e
            @output.puts "ElasticSearch upload error: #{e}"
            @logger.error "ElasticSearch upload error: #{e}" if @logger
          end
        end

      end

      @output.puts "Wrote #{@vault.size} entries.\n\n"
      @logger.info "Wrote #{@vault.size} entries." if @logger
      @vault.clear

    end

  end

end
