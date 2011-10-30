-define(LOG_PREFIX, [{module, ?MODULE}, {line, ?LINE}, {pid, self()}]).
-define(INFO(Args), error_logger:info_report(?LOG_PREFIX ++ Args)).
-define(WARN(Args), error_logger:warning_report(?LOG_PREFIX ++ Args)).
-define(ERROR(Args), error_logger:error_report(?LOG_PREFIX ++ Args)).
