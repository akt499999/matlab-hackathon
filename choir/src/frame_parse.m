function f = frame_parse(bits, P)
%FRAME_PARSE Check the CRC and read spacecraft ID, frame count and telemetry from 1784 frame bits.
[msg, err] = crcDetect(double(bits(:)), P.crc);
bytes = uint8(bit2int(msg, 8));
w1 = bitor(bitshift(uint16(bytes(1)), 8), uint16(bytes(2)));
f.crcOK = ~err;
f.scid  = double(bitand(bitshift(w1, -4), 1023));
f.count = double(bytes(3));
f.q     = swapbytes(typecast(bytes(8:221).', 'int16')).';
end
