## implementation of https://www.ietf.org/rfc/rfc9000.html
## QUIC is a name, not an acronym.
import strutils

import connection_id
import read_utils
import hdkf
import protection

# type
#   Endpoint = enum
#     ## An entity that can participate in a QUIC connection by generating,
#     ## receiving, and processing QUIC packets.
#     ## There are only two types of endpoints in QUIC: client and server.
#     client
#       ## The endpoint that initiates a QUIC connection.
#     server
#       ## The endpoint that accepts a QUIC connection.
#   Direction = enum
#     unidirectional
#     bidirectional
#   StreamState = enum
#     none
#   StreamID {.size: 8.} = object
#     id: int ## 2^62
#     endpoint: Endpoint # 1 bit
#     direction: Direction # 1 bit
#   Stream = object
#     ## A unidirectional or bidirectional channel of ordered bytes within a QUIC connection.
#     ## A QUIC connection can carry multiple simultaneous streams.
#     id: StreamID
#     state: StreamState
#     priority: int
#       ## A QUIC implementation SHOULD provide ways
#       ## in which an application can indicate the relative priority of streams.
#       ## An implementation uses information provided by the application
#       ## to determine how to allocate resources to active streams.


#   Connection = object
#   ConnectionID = object
#     ## An identifier that is used to identify a QUIC connection at an endpoint.
#     ## Each endpoint selects one or more connection IDs for its peer to include
#     ## in packets sent towards the endpoint.
#     ## This value is opaque to the peer.
#   Packet = object
#     ## A complete processable unit of QUIC that can be encapsulated in a UDP datagram.
#     ## One or more QUIC packets can be encapsulated in a single UDP datagram.
#     ## 
#     ## Ack-eliciting packet:
#     ## A QUIC packet that contains frames other than ACK, PADDING, and CONNECTION_CLOSE.
#     ## These cause a recipient to send an acknowledgment; see Section 13.2.1.
#   Frame = object
#     ## A unit of structured protocol information.
#     ## There are multiple frame types, each of which carries different information.
#     ## Frames are contained in QUIC packets.
#     id: StreamID
#     offset: int ## to place data in order
#   Error = enum
#     PROTOCOL_VIOLATION
#       ## receipt of different data at the same offset within a stream
#   Address = object
#     ## When used without qualification, the tuple of IP version,
#     ## IP address, and UDP port number that represents one end of a network path.
  

# OPS

# write
# end
# reset

# read
# abort

# EVENTS

# state changed
# opened stream
# stream reset
# aborted
# new data is available

# data can or cannot be written to the stream due to flow control (draining)

## On the sending part of a stream, an application protocol can:

# write data, understanding when stream flow control credit (Section 4.1) has successfully been reserved to send the written data;
# end the stream (clean termination), resulting in a STREAM frame (Section 19.8) with the FIN bit set; and
# reset the stream (abrupt termination), resulting in a RESET_STREAM frame (Section 19.4) if the stream was not already in a terminal state.
# On the receiving part of a stream, an application protocol can:

# read data; and
# abort reading of the stream and request closure, possibly resulting in a STOP_SENDING frame (Section 19.5).
# An application protocol can also request to be informed of state changes on streams,
# including when the peer has opened or reset a stream, when a peer aborts reading on a stream,
# when new data is available, and when data can or cannot be written to the stream due to flow control.

# Frames

# BIG TODO: PROTOCOL_VIOLATION

type
  # https://www.ietf.org/rfc/rfc9000.html#name-frames-and-frame-types
  FrameType* = enum
    framePadding
    framePing
    frameAck
    frameResetStream
    frameStopSending
    frameCrypto
    frameNewToken
    frameStream
    frameMaxData
    frameMaxStreamData
    frameMaxStreams
    frameDataBlocked
    frameStreamDataBlocked
    frameStreamsBlocked
    frameNewConnectionID
    frameRetireConnectionID
    framePathChallenge
    framePathResponse
    frameConnectionClose
    frameHandshakeDone
  
  Frame = object

import std/math

const
  PacketKindMask = 0b11110000
  TPacket1RTT = 0b01000000
  TPacketVersionNegotiation = 0b10000000
  TPacketInitial = 0b11000000
  TPacket0RTT = 0b11010000
  TPacketHandshake = 0b11100000
  TPacketRetry = 0b11110000

type
  PacketKind* = enum
    packet1RTT
    packetVersionNegotiation
    packetInitial
    packet0RTT
    packetHandshake
    packetRetry
  
  PacketNumber* = range[0..2^62-1]

  PacketInitial* = object
    version*: uint32
    destination: ConnectionId
    source: ConnectionId
    token*: seq[byte]
    packetnumber*: PacketNumber
    payload: seq[byte]
    # frames*: seq[Frame]
  
  Packet1RTT* = object
    spinBit* {.bitsize: 1.}: bool
    packetNumberLength* {.bitsize: 1.}: uint8
    packetnumber*: PacketNumber
    # frames*: seq[Frame]

  Packet0RTT* = object
    version*: uint32
    packetnumber*: PacketNumber
    # frames*: seq[Frame]

  PacketHandshake* = object
    version*: uint32
    packetnumber*: PacketNumber
    # frames*: seq[Frame]

  PacketRetry* = object
    version*: uint32
    token*: seq[byte]
    integrity*: array[16, byte]

  PacketVersionNegotiation* = object
    supportedVersions*: seq[uint32]
  
  Packet* = object
    case kind*: PacketKind
    of packet1RTT:
      rtt1: Packet1RTT
    of packetVersionNegotiation:
      negotiation: PacketVersionNegotiation
    of packetInitial:
      initial: PacketInitial
    of packet0RTT:
      rtt: Packet0RTT
    of packetHandshake:
      handshake: PacketHandshake
    of packetRetry:
      retry: PacketRetry


proc readFrame(offset: var ptr): Frame =
  let frameType = read[byte](offset)
  echo frameType.toHex
  result = Frame()

type
  Secret = object
    secret: string
    key: string
    iv: string
    hp: string
  InitialKeys = object
    client: Secret
    server: Secret
  

const
  salt29 = "38762cf7f55934b34d179ae6a4c80cadccbb7f0a".parseHexStr
  salt30 = "afbfec289993d24c9e9786f19c6111e04390a899".parseHexStr

proc getInitialKeys(header: PacketInitial): InitialKeys =
  # TODO: поэкспериментировать с тем чтобы передавать отдельно
  # header.version и header.destination
  result = InitialKeys()
  let initial_salt = if (header.version and 0xff000000.uint32) > 0:
      salt29
    else:
      salt30
  let initial_random = cast[string](header.destination)
  let initial_secret = hdkfExtract(initial_salt, initial_random)
  result.client.secret = hdkfExpandLabel(initial_secret, "tls13 client in", 32)
  result.server.secret = hdkfExpandLabel(initial_secret, "tls13 server in", 32)
  result.client.key = hdkfExpandLabel(result.client.secret, "tls13 quic key", 16)
  result.server.key = hdkfExpandLabel(result.server.secret, "tls13 quic key", 16)
  result.client.iv = hdkfExpandLabel(result.client.secret, "tls13 quic iv", 12)
  result.server.iv = hdkfExpandLabel(result.server.secret, "tls13 quic iv", 12)
  result.client.hp = hdkfExpandLabel(result.client.secret, "tls13 quic hp", 16)
  result.server.hp = hdkfExpandLabel(result.server.secret, "tls13 quic hp", 16)


proc parsePacket*(buf: ptr): Packet =
  var offset = buf
  let firstByte = read[byte](offset)
  case firstByte and PacketKindMask
  of TPacketVersionNegotiation:
    result = Packet(kind: packetVersionNegotiation)
  of TPacketInitial:
    result = Packet(kind: packetInitial)
    result.initial.version = read[uint32](offset)
    result.initial.destination = cast[ConnectionId](readSeq[uint8](offset))
    result.initial.source = cast[ConnectionId](readSeq[uint8](offset))
    let tokenLen = readVarInt(offset)
    result.initial.token = readSeq(offset, tokenLen)
    let payloadLen = readVarInt(offset)

    let initialKeys = getInitialKeys(result.initial)
    let sample = cast[string](readSeq(offset+4, 16))
    let mask = headerProtection(initialKeys.client.hp, sample)
    
    let pnLen = (firstByte xor mask[0].byte) and 0b00000011 + 1
    result.initial.packetNumber = readPacketNumber(offset, pnLen.int, mask)
    offset = offset + pnLen

    result.initial.payload = readSeq(offset, payloadLen)
    let authtag = readSeq(offset, 16)

    aes128gcmDecrypt(
      initialKeys.client.key,
      initialKeys.client.iv,
      cast[string](result.initial.payload),
      cast[string](authtag)
    )

    discard readFrame(offset)
    # payload only permit CRYPTO, ACK, PING, PADDING, CONNECTION_CLOSE
  of TPacket0RTT:
    result = Packet(kind: packet0RTT)
  of TPacketHandshake:
    result = Packet(kind: packetHandshake)
  of TPacketRetry:
    result = Packet(kind: packetRetry)
  elif (firstByte and TPacket1RTT) > 0:
    result = Packet(kind: packet1RTT)
  else:
    echo "Error"

  # if cast[PacketForm](firstByte shr 7) == formLong:
  #   result = Packet(form: formLong, kind: cast[PacketKind]((firstByte and 0b01100000) shr 6))
  # else:
  #   result = Packet(form: formShort)