function s4 = kr_s4(v)
%KR_S4  SSSS region of each integer value [Table 3.7]:
%   0 for 0, otherwise the number of bits of |v| (1 for +-1, 2 for +-2..3, ...),
%   capped at 15. (|v| = 32768 has no region in Kiem's table; it is capped.)
a  = abs(v);
s4 = zeros(size(v));
nz = a > 0;
s4(nz) = floor(log2(a(nz))) + 1;
s4 = min(s4, 15);
end
