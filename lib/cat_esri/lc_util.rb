require "digest/md5"
require "socket"

module CatEsri
  # A collection of utility methods
  
  #----------
  # Construct an MD5 checksum based on all bytes if the file is < CS_MAXMB or
  # on smaller chunks from the head and tail if the file is > CS_MAXMB.
  CS_MAXMB = 25 * 1024**2
  CS_CHUNK = CS_MAXMB * 0.25
  def checksum(path)
    return nil unless File.exist?(path)
    return nil if File.directory?(path)
    begin
      inc_digest = Digest::MD5.new
      cs = "unset"
      b = File.size(path)    
      f = File.open(path, 'rb')
      if (b < CS_MAXMB)
        # small enough. read entire file
        inc_digest << f.read
        cs = inc_digest.hexdigest
      elsif (b > CS_MAXMB && b < 2**30) 
        # checksum just chunks. one from head, one from tail
        inc_digest << f.read(CS_CHUNK)
        f.pos = b-(CS_CHUNK)
        inc_digest << f.read(CS_CHUNK)
        cs = inc_digest.hexdigest
      elsif (b > 2**30)
        # file is too big for File.pos (which needs a long, not Bignum)
        inc_digest << f.read(CS_MAXMB)
        cs = inc_digest.hexdigest
      end
      f.close
      return cs
    rescue Exception => e
      raise e
    end
  end
  
  
  #----------
  # Just a hostname.
  def hostname
    Socket.gethostname
  end
  
  #----------
  # use with Find/prune to avoid getting kicked out of recursion due to 
  # inaccessible folders
  def inaccessible_dir?(d)
    return if File.file?(d)
    begin
      Dir.open(File.join(d,'.'))
    rescue Errno::EACCES
      return true
    end
    return false
  end
  
  #----------
  # Accept an array of strings (or possibly other arrays) and chop the whole thing
  # down to a cloud of unstructured unique "words" with most troublesome chars and numerics 
  # stripped out. This cloud can be used for text search indexes on data types that may not 
  # necessarily contain formatted text and have a lot of redundancy (like shapefiles).
  def get_uniq_cloud(a)
    ucloud = []
    # some golf to yield a single array of unique stings
    a.flatten.uniq.join(' ').scan(/\w+/).uniq.each do |x|
      s = x.strip
      # keep 10 and 14 digit UWIs
      #ucloud << s if s =~ /^\d{10}$|^\d{14}$/
      ucloud << s if s =~ /\d{10}00\d{2}|\d{10}/
      # keep string unless it is a number or too short (<2 chars)
      ucloud << s unless s =~ /[-+]?\d*\.?\d+/ || s.length < 2
    end
    return ucloud.join(' ')
  end
  
  
  #----------
  # Basically like checksum, but accepts a string and doesn't worry about size.
  # Slashes are normalized to prevent unix/windows/ruby slash weirdness.
  def guidify(s)
    inc_digest = Digest::MD5.new
    inc_digest << s.downcase.gsub('/','').gsub('\\','') 
    return inc_digest.hexdigest
  end
  
  
  #----------
  # Tokenize a string in a somewhat ridiculous way. This allows all the chunks of 
  # files with complex naming conventions (even short fragments) to get parsed with 
  # conservative lexers.
  def mince(s)
    x = ""
    s.each_byte do |b|
      case b
      when 0
        x << " "
      when (1..47)
        x << " "      
      when (48..57)
        x << b.chr
      when (58..64)
        x << " "
      when (65..90)
        x << b.chr
      when (91..96)
        x << " "
      when (97..122)
        x << b.chr
      end
    end
    return x.squeeze(' ').strip
  end
  
  
  #----------
  # Paranoid removal of scary characters and stringification of hash keys for
  # easier digestion into sqlite and csv formats.
  def scrub_values(h)
    h.each_pair { |k,v| h[k] = v.to_s.encode("UTF-8", undef: :replace, replace: "?") unless v.nil?}
    h.each_pair {|k,v| h[k] = v.to_s.gsub('\'','').gsub('\`','').gsub(',','').gsub('\"','').gsub('|','').strip }
  end
  
  #----------
  # use consistent slashes depending on OS
  def normal_seps(s)
    sep = '/'
    sep = '\\' if @os == "mingw32"
    return s.gsub('/',sep).gsub('\\',sep)
  end



  #----------
  # convenience class for dealing with MS Access via ADO on Windows
  # http://rubyonwindows.blogspot.com/2007/06/using-ruby-ado-to-work-with-ms-access.html
  class AccessDb
    
    attr_accessor :mdb, :connection, :data, :fields

    def initialize(mdb=nil)
      @mdb = mdb
      @connection = nil
      @data = nil
      @fields = nil
    end

    def open
      connection_string = 'Provider=Microsoft.Jet.OLEDB.4.0;Data Source='
      connection_string << @mdb
      @connection = WIN32OLE.new('ADODB.Connection')
      @connection.Open(connection_string)
    end

    def query(sql)
      recordset = WIN32OLE.new('ADODB.Recordset')
      recordset.Open(sql, @connection)
      @fields = []
      recordset.Fields.each do |field|
        @fields << field.Name
      end
      begin
        @data = recordset.GetRows.transpose
      rescue
        @data = []
      end      
      recordset.Close
    end

    def execute(sql)
      begin
        @connection.Execute(sql)
      rescue Exception => e
        raise e
      end
    end

    def close
      @connection.Close
    end
    
  end

end

