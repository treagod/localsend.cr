require "log"

module LocalSend
  # Sub-loggers so an application can turn up just the part it cares about,
  # e.g. `Log.setup("localsend.tls", :debug)`.
  Log = ::Log.for("localsend")
end
