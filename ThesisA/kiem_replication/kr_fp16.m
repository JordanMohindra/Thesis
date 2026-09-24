function Y = kr_fp16(X)
%KR_FP16  Kiem's reference format FP16 [3.4.1]: IEEE 754 half precision.
%   X is in 32-bit full-scale units. It is normalised so that full scale is
%   1.0, rounded to the half-precision grid (10 stored mantissa bits,
%   subnormals down to 2^-24), and scaled back. Written out explicitly so no
%   toolbox is needed; values beyond 65504 cannot occur after normalisation.
s  = 2^31;
Y  = complex(halfround(real(X)/s), halfround(imag(X)/s)) * s;
end

function y = halfround(x)
a = abs(x);
e = floor(log2(a + (a == 0)));
q = 2.^max(e - 10, -24);             % spacing of the half-precision grid
y = sign(x) .* round(a ./ q) .* q;
y(a == 0) = 0;
end
