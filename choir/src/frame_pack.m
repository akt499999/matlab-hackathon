function [bits, q] = frame_pack(vals, count, scid, P)
%FRAME_PACK One CCSDS-style TM transfer frame: 6-byte primary header, channel byte,
%   107 big-endian int16 telemetry samples, CRC-16 (x^16+x^12+x^5+1). 223 bytes = 1784 bits.
q = int16(round(max(min(vals(:), 1), -1) * 32767));
w1 = bitshift(uint16(scid), 4);                         % version 00 | spacecraft ID (10) | VC 0 | OCF 0
hdr = uint8([bitshift(w1, -8); bitand(w1, 255); mod(count, 256); mod(count, 256); 0; 0]);
payload = typecast(swapbytes(q).', 'uint8').';
body = [hdr; uint8(1); payload];                        % 6 + 1 + 214 = 221 bytes
bits = logical(crcGenerate(int2bit(double(body), 8), P.crc));
end
