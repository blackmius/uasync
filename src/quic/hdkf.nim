import bearssl

proc hdkfExtract*(salt: string; ikm: string): string =
  ## RFC 5869 section 2.2
  ## 
  ## HKDF-Extract(salt, IKM) -> PRK
  ## 
  ## Options:
  ##    Hash     a hash function; HashLen denotes the length of the
  ##             hash function output in octets
  ## Inputs:
  ##    salt     optional salt value (a non-secret random value);
  ##             if not provided, it is set to a string of HashLen zeros.
  ##    IKM      input keying material
  ## 
  ## Output:
  ##    PRK      a pseudorandom key (of HashLen octets)
  ## 
  ## The output PRK is calculated as follows:
  ##    PRK = HMAC-Hash(salt, IKM)
  ## 
  result = newString(32)
  var h: HmacContext
  var hk: HmacKeyContext
  hmacKeyInit(hk, sha256Vtable.addr, salt[0].addr, salt.len.uint)
  hmacInit(h, hk, 32)
  hmacUpdate(h, ikm[0].addr, ikm.len.uint)
  assert hmacOut(h, result[0].addr) > 0

proc hdkfExpandLabel*(key: string; label: string; len: int): string =
  ### RFC 8446 section 7.1
  ##
  ## The key derivation process makes use of the HKDF-Extract and
  ## HKDF-Expand functions as defined above, as well as the
  ## functions defined below:
  ##
  ## HKDF-Expand-Label(Secret, Label, Context, Length) =
  ##   HKDF-Expand(Secret, HkdfLabel, Length)
  ##
  ## Where HkdfLabel is specified as:
  ##
  ## struct {
  ##   uint16 length = Length;
  ##   opaque label<7..255> = "tls13 " + Label;
  ## 	 opaque context<0..255> = Context;
  ## } HkdfLabel;
  ##
  ## implementor's note: the above definition references variable-length vectors,
  ## which in this case are preceded by a single-byte of length info.
  ## 
  ## FROM https://quic.xargs.org/#client-initial-keys-calc
  ## 
  result = newString(len)
  var h: HmacContext
  var hk: HmacKeyContext
  hmacKeyInit(hk, sha256Vtable.addr, key[0].addr, key.len.uint)
  hmacInit(h, hk, len.uint)
  let data = (len shr 8).char & len.char & label.len.char & label & 0.char & 1.char
  hmacUpdate(h, data[0].addr, data.len.uint)
  assert hmacOut(h, result[0].addr) > 0

  # var h: HkdfContext
  # hkdfInit(h, sha256Vtable.addr, key[0].addr, key.len.uint)
  # var data = (len shr 8).char & len.char & (label.len + 6).char & "tls13 " & label & 0.char & 1.char
  # hkdfInject(h, data[0].addr, data.len.uint)
  # echo "hkdfLabel=", data.toHex
  # hkdfFlip(h)
  # result = newString(len)
  # assert hkdfProduce(h, nil, 0, result[0].addr, result.len.uint) > 0

when isMainModule:
  import strutils

  let initial_salt = "38762cf7f55934b34d179ae6a4c80cadccbb7f0a".parseHexStr
  let initial_random = "0001020304050607".parseHexStr
  let initial_secret = hdkfExtract(initial_salt, initial_random)
  let client_secret = hdkfExpandLabel(initial_secret, "tls13 client in", 32)
  let server_secret = hdkfExpandLabel(initial_secret, "tls13 server in", 32)
  let client_key = hdkfExpandLabel(client_secret, "tls13 quic key", 16)
  let server_key = hdkfExpandLabel(server_secret, "tls13 quic key", 16)
  let client_iv = hdkfExpandLabel(client_secret, "tls13 quic iv", 12)
  let server_iv = hdkfExpandLabel(server_secret, "tls13 quic iv", 12)
  let client_hp_key = hdkfExpandLabel(client_secret, "tls13 quic hp", 16)
  let server_hp_key = hdkfExpandLabel(server_secret, "tls13 quic hp", 16)

  echo "initial_secret=", initial_secret.toHex
  echo "client_secret=", client_secret.toHex
  echo "server_secret=", server_secret.toHex
  echo "client_key=", client_key.toHex
  echo "server_key=", server_key.toHex
  echo "client_iv=", client_iv.toHex
  echo "server_iv=", server_iv.toHex
  echo "client_hp_key=", client_hp_key.toHex
  echo "server_hp_key=", server_hp_key.toHex