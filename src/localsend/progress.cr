module LocalSend
  # Upload progress for one file, passed to `Client#send`'s block.
  struct Progress
    getter file_name : String
    getter bytes : Int64
    getter total : Int64

    def initialize(@file_name, @bytes, @total)
    end

    def percent : Int32
      return 100 if @total <= 0
      (@bytes * 100 // @total).clamp(0, 100).to_i
    end

    def done? : Bool
      @bytes >= @total
    end
  end

  # Wraps an upload body and reports bytes as it is read.
  private class ProgressIO < IO
    def initialize(@source : IO, @file_name : String, @total : Int64, &@report : Progress ->)
      @bytes = 0_i64
    end

    def read(slice : Bytes) : Int32
      count = @source.read slice
      if count > 0
        @bytes += count
        @report.call Progress.new(@file_name, @bytes, @total)
      end
      count
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new "ProgressIO is read-only"
    end
  end
end
