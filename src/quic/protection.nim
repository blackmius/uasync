import bearssl

proc headerProtection*(hp: string, sample: string): string =
  # aes-128-ecb
  var keys: AesBigCbcencKeys
  aesBigCbcencInit(keys, hp[0].addr, hp.len.uint)
  result = newString(16)
  keys.aesBigCbcencRun(result[0].addr, sample[0].addr, 16)

import strutils
when isMainModule:

  let hp = "6df4e9d737cdf714711d7c617ee82981".parseHexStr
  let sample = "ed78716be9711ba498b7ed868443bb2e".parseHexStr

  echo headerProtection(hp, sample).toHex

proc aes128gcmDecrypt*(key: string, iv: string, data: string, tag: string) =
  var bctx: AesBigCtrKeys
  aesBigCtrInit(bctx, key[0].addr, key.len.uint)

  var gcm: GcmContext
  gcmInit(gcm, bctx.vtable.addr, ghashCtmul)
  gcmReset(gcm, iv[0].addr, iv.len.uint)
  gcmFlip(gcm)
  gcmRun(gcm, 0, data[0].addr, data.len.uint)
  echo data.toHex
  echo gcmCheckTag(gcm, tag[0].addr)
  