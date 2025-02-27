require "digest/digest"

# Implements the MD5 digest algorithm.
#
# WARNING: MD5 is no longer a cryptographically secure hash, and should not be
# used in security-related components, like password hashing. For passwords, see
# `Crypto::Bcrypt::Password`. For a generic cryptographic hash, use SHA-256 via
# `OpenSSL::Digest.new("SHA256")`.
class Crystal::Digest::MD5 < ::Digest
  extend ::Digest::ClassMethods

  @i = StaticArray(UInt32, 2).new(0_u32)
  @buf = StaticArray(UInt32, 4).new(0_u32)
  @in = StaticArray(UInt8, 64).new(0_u8)

  def initialize
    reset
  end

  private def reset_impl : Nil
    @i[0] = 0_u32
    @i[1] = 0_u32
    @buf[0] = 0x67452301_u32
    @buf[1] = 0xEFCDAB89_u32
    @buf[2] = 0x98BADCFE_u32
    @buf[3] = 0x10325476_u32
  end

  private def update_impl(data : Bytes) : Nil
    update(data.to_unsafe, data.bytesize.to_u32)
  end

  private def update(inBuf, inLen)
    tmp_in = uninitialized UInt32[16]

    # compute number of bytes mod 64
    mdi = (@i[0] >> 3) & 0x3F

    # update number of bits
    @i[1] &+= 1 if (@i[0] &+ (inLen << 3)) < @i[0]
    @i[0] &+= (inLen << 3)
    @i[1] &+= (inLen >> 29)

    inLen.times do
      # add new character to buffer, increment mdi
      @in[mdi] = inBuf.value
      mdi += 1
      inBuf += 1

      # transform if necessary
      if mdi == 0x40
        ii = 0
        16.times do |i|
          tmp_in[i] = (@in[ii + 3].to_u32 << 24) |
                      (@in[ii + 2].to_u32 << 16) |
                      (@in[ii + 1].to_u32 << 8) |
                      (@in[ii])
          ii += 4
        end
        transform tmp_in
        mdi = 0
      end
    end
  end

  S11 =  7
  S12 = 12
  S13 = 17
  S14 = 22

  S21 =  5
  S22 =  9
  S23 = 14
  S24 = 20

  S31 =  4
  S32 = 11
  S33 = 16
  S34 = 23

  S41 =  6
  S42 = 10
  S43 = 15
  S44 = 21

  private PADDING = begin
    padding = StaticArray(UInt8, 64).new(0_u8)
    padding[0] = 0x80_u8
    padding
  end

  private def f(x, y, z)
    (x & y) | ((~x) & z)
  end

  private def g(x, y, z)
    (x & z) | (y & (~z))
  end

  private def h(x, y, z)
    x ^ y ^ z
  end

  private def i(x, y, z)
    y ^ (x | (~z))
  end

  private def ff(a, b, c, d, x, s, ac)
    a &+= f(b, c, d) &+ x &+ ac.to_u32
    a = a.rotate_left s
    a &+= b
  end

  private def gg(a, b, c, d, x, s, ac)
    a &+= g(b, c, d) &+ x &+ ac.to_u32
    a = a.rotate_left s
    a &+= b
  end

  private def hh(a, b, c, d, x, s, ac)
    a &+= h(b, c, d) &+ x &+ ac.to_u32
    a = a.rotate_left s
    a &+= b
  end

  private def ii(a, b, c, d, x, s, ac)
    a &+= i(b, c, d) &+ x &+ ac.to_u32
    a = a.rotate_left s
    a &+= b
  end

  private def transform(input)
    a, b, c, d = @buf

    # Round 1
    a = ff(a, b, c, d, input[0], S11, 3614090360)  # 1
    d = ff(d, a, b, c, input[1], S12, 3905402710)  # 2
    c = ff(c, d, a, b, input[2], S13, 606105819)   # 3
    b = ff(b, c, d, a, input[3], S14, 3250441966)  # 4
    a = ff(a, b, c, d, input[4], S11, 4118548399)  # 5
    d = ff(d, a, b, c, input[5], S12, 1200080426)  # 6
    c = ff(c, d, a, b, input[6], S13, 2821735955)  # 7
    b = ff(b, c, d, a, input[7], S14, 4249261313)  # 8
    a = ff(a, b, c, d, input[8], S11, 1770035416)  # 9
    d = ff(d, a, b, c, input[9], S12, 2336552879)  # 10
    c = ff(c, d, a, b, input[10], S13, 4294925233) # 11
    b = ff(b, c, d, a, input[11], S14, 2304563134) # 12
    a = ff(a, b, c, d, input[12], S11, 1804603682) # 13
    d = ff(d, a, b, c, input[13], S12, 4254626195) # 14
    c = ff(c, d, a, b, input[14], S13, 2792965006) # 15
    b = ff(b, c, d, a, input[15], S14, 1236535329) # 16

    # Round 2
    a = gg(a, b, c, d, input[1], S21, 4129170786)  # 17
    d = gg(d, a, b, c, input[6], S22, 3225465664)  # 18
    c = gg(c, d, a, b, input[11], S23, 643717713)  # 19
    b = gg(b, c, d, a, input[0], S24, 3921069994)  # 20
    a = gg(a, b, c, d, input[5], S21, 3593408605)  # 21
    d = gg(d, a, b, c, input[10], S22, 38016083)   # 22
    c = gg(c, d, a, b, input[15], S23, 3634488961) # 23
    b = gg(b, c, d, a, input[4], S24, 3889429448)  # 24
    a = gg(a, b, c, d, input[9], S21, 568446438)   # 25
    d = gg(d, a, b, c, input[14], S22, 3275163606) # 26
    c = gg(c, d, a, b, input[3], S23, 4107603335)  # 27
    b = gg(b, c, d, a, input[8], S24, 1163531501)  # 28
    a = gg(a, b, c, d, input[13], S21, 2850285829) # 29
    d = gg(d, a, b, c, input[2], S22, 4243563512)  # 30
    c = gg(c, d, a, b, input[7], S23, 1735328473)  # 31
    b = gg(b, c, d, a, input[12], S24, 2368359562) # 32

    # Round 3
    a = hh(a, b, c, d, input[5], S31, 4294588738)  # 33
    d = hh(d, a, b, c, input[8], S32, 2272392833)  # 34
    c = hh(c, d, a, b, input[11], S33, 1839030562) # 35
    b = hh(b, c, d, a, input[14], S34, 4259657740) # 36
    a = hh(a, b, c, d, input[1], S31, 2763975236)  # 37
    d = hh(d, a, b, c, input[4], S32, 1272893353)  # 38
    c = hh(c, d, a, b, input[7], S33, 4139469664)  # 39
    b = hh(b, c, d, a, input[10], S34, 3200236656) # 40
    a = hh(a, b, c, d, input[13], S31, 681279174)  # 41
    d = hh(d, a, b, c, input[0], S32, 3936430074)  # 42
    c = hh(c, d, a, b, input[3], S33, 3572445317)  # 43
    b = hh(b, c, d, a, input[6], S34, 76029189)    # 44
    a = hh(a, b, c, d, input[9], S31, 3654602809)  # 45
    d = hh(d, a, b, c, input[12], S32, 3873151461) # 46
    c = hh(c, d, a, b, input[15], S33, 530742520)  # 47
    b = hh(b, c, d, a, input[2], S34, 3299628645)  # 48

    # Round 4
    a = ii(a, b, c, d, input[0], S41, 4096336452)  # 49
    d = ii(d, a, b, c, input[7], S42, 1126891415)  # 50
    c = ii(c, d, a, b, input[14], S43, 2878612391) # 51
    b = ii(b, c, d, a, input[5], S44, 4237533241)  # 52
    a = ii(a, b, c, d, input[12], S41, 1700485571) # 53
    d = ii(d, a, b, c, input[3], S42, 2399980690)  # 54
    c = ii(c, d, a, b, input[10], S43, 4293915773) # 55
    b = ii(b, c, d, a, input[1], S44, 2240044497)  # 56
    a = ii(a, b, c, d, input[8], S41, 1873313359)  # 57
    d = ii(d, a, b, c, input[15], S42, 4264355552) # 58
    c = ii(c, d, a, b, input[6], S43, 2734768916)  # 59
    b = ii(b, c, d, a, input[13], S44, 1309151649) # 60
    a = ii(a, b, c, d, input[4], S41, 4149444226)  # 61
    d = ii(d, a, b, c, input[11], S42, 3174756917) # 62
    c = ii(c, d, a, b, input[2], S43, 718787259)   # 63
    b = ii(b, c, d, a, input[9], S44, 3951481745)  # 64

    @buf[0] &+= a
    @buf[1] &+= b
    @buf[2] &+= c
    @buf[3] &+= d
  end

  private def final_impl(dst : Bytes) : Nil
    tmp_in = uninitialized UInt32[16]

    # save number of bits
    tmp_in[14] = @i[0]
    tmp_in[15] = @i[1]

    # compute number of bytes mod 64
    mdi = ((@i[0] >> 3) & 0x3F).to_i32

    # pad out to 56 mod 64
    pad_len = (mdi < 56) ? (56 - mdi) : (120 - mdi)
    update PADDING.to_unsafe, pad_len

    # append length in bits and transform
    ii = 0
    14.times do |i|
      tmp_in[i] = (@in[ii + 3].to_u32 << 24) |
                  (@in[ii + 2].to_u32 << 16) |
                  (@in[ii + 1].to_u32 << 8) |
                  (@in[ii])
      ii += 4
    end
    transform tmp_in

    # store buffer in digest
    ii = 0
    4.times do |i|
      dst[ii] = (@buf[i] & 0xff).to_u8
      dst[ii + 1] = ((@buf[i] >> 8) & 0xFF).to_u8
      dst[ii + 2] = ((@buf[i] >> 16) & 0xFF).to_u8
      dst[ii + 3] = ((@buf[i] >> 24) & 0xFF).to_u8
      ii += 4
    end
  end

  def digest_size : Int32
    16
  end
end
