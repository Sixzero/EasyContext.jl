
const DATE_FORMAT_REGEX = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:z|Z)?"
const DATE_FORMAT::String = "yyyy-mm-ddTHH:MM:SS.sssZ"

const MSG_FORMAT::Regex = r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+Z)?) \[(\w+), id: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}), in: (\d+), out: (\d+), cached: (\d+), cache_read: (\d+), price: ([\d.]+), elapsed: ([\d.]+)\]: (.+)"s

const CONVERSATION_FILE_REGEX = Regex("^($(DATE_FORMAT_REGEX.pattern))_(?<sent>.*)_(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\\.log\$")

date_format(date) = Dates.format(date, DATE_FORMAT)
date_parse(date)  = try DateTime(date, DATE_FORMAT) catch e; (println(date); println(e); rethrow(e);) end

