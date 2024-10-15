using Dates
using ULID: encodetime, encoderandom

short_ulid() = encodetime(floor(Int,datetime2unix(now())*1000),10)*encoderandom(8)
short_ulid()