{.compile: "picohttpparser.c"}

{.push header: "picohttpparser.h".}

type
  Header* {.importc: "struct phr_header", bycopy.} = object
    name* {.importc: "name".}: cstring
    nameLen* {.importc: "name_len".}: csize_t
    value* {.importc: "value".}: cstring
    valueLen* {.importc: "value_len".}: csize_t


proc parseRequest*(buf: cstring; len: csize_t; `method`: ptr cstring;
                   methodLen: ptr csize_t; path: ptr cstring; pathLen: ptr csize_t;
                   minorVersion: ptr cint; headers: ptr Header;
                   numHeaders: ptr csize_t; lastLen: csize_t): cint {.cdecl,
  importc: "phr_parse_request".}

proc parseResponse*(buf: cstring; len: csize_t; minorVersion: ptr cint;
                    status: ptr cint; msg: ptr cstring; msgLen: ptr csize_t;
                    headers: ptr Header; numHeaders: ptr csize_t; lastLen: csize_t): cint {.
  cdecl, importc: "phr_parse_response".}

proc parseHeaders*(buf: cstring; len: csize_t; headers: ptr Header;
                   numHeaders: ptr csize_t; lastLen: csize_t): cint {.cdecl,
  importc: "phr_parse_headers".}

type
  ChunkedDecoder* {.importc: "struct phr_chunked_decoder", bycopy.} = object
    bytesLeftInChunk* {.importc: "bytes_left_in_chunk".}: csize_t
    consumeTrailer* {.importc: "consume_trailer".}: char
    hexCount* {.importc: "_hex_count".}: char
    state* {.importc: "_state".}: char


proc decodeChunked*(decoder: ptr ChunkedDecoder; buf: cstring; bufsz: ptr csize_t): int {.
  cdecl, importc: "phr_decode_chunked".}

proc decodeChunkedIsInData*(decoder: ptr ChunkedDecoder): cint {.cdecl,
  importc: "phr_decode_chunked_is_in_data".}

{.pop.}
