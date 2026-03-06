require "./device"
require "./log"
require "./protocol/prepare_upload"

module LocalSend
  # A proposed transfer, waiting for the application to decide.
  class IncomingTransfer
    Log = LocalSend::Log.for("receiver")

    # Reject transfers left unanswered for five minutes.
    DECIDE_WITHIN = 5.minutes

    record File, id : String, name : String, size : Int64, type : String

    getter device : Device
    getter files : Array(File)

    @decision = Channel(Path?).new(1)
    @decided = false

    def initialize(@device, @files)
    end

    def total_size : Int64
      @files.sum(&.size)
    end

    # Accepts the transfer and stores its files in *directory*.
    def accept(directory : Path) : Nil
      decide directory
    end

    def reject : Nil
      decide nil
    end

    def decided? : Bool
      @decided
    end

    # Waits for the application's choice. Applications call `#accept` or
    # `#reject`; `Receiver` calls this method.
    def await_decision : Path?
      select
      when destination = @decision.receive
        destination
      when timeout(DECIDE_WITHIN)
        Log.info { "no decision for #{@device} within #{DECIDE_WITHIN}, rejecting" }
        @decided = true
        nil
      end
    end

    private def decide(destination : Path?)
      raise Error.new "transfer was already decided" if @decided
      @decided = true
      @decision.send destination
    end
  end
end
