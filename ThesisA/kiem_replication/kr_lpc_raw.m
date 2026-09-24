function out = kr_lpc_raw(adc, p)
%KR_LPC_RAW  LPC-Huffman as Kiem describes it in his Section 2.7.4 (the
%   method of his reference [25], Meucci and Mancuso): linear prediction of
%   each RAW ADC sample from the previous p samples of the same chirp (fast
%   time), least-squares (autocorrelation / Levinson-Durbin) coefficients, and
%   Huffman coding of the residual with a dictionary computed for the input.
%   Kiem did not run this method; he excluded it from his design space
%   because it "has the same approach as DRHE, but ... operates on raw ADC
%   data" [3.4.1]. ASSUMPTIONS: one coefficient set per chirp and receiver,
%   sent as single-precision floats (32 bits each); the Huffman dictionary is
%   sent once per frame as (value, length) pairs of 16 + 5 bits, and the CR
%   is also given without it.
%   adc: int16 [numSamples x numRamps x numRx] raw codes (not shifted).
x = double(reshape(adc, size(adc, 1), []));   % one column per chirp
[N, C] = size(x);
% autocorrelation r(0..p) of every chirp
r = zeros(p + 1, C);
for k = 0:p
    r(k+1, :) = sum(x(1+k:N, :) .* x(1:N-k, :), 1);
end
% Levinson-Durbin, vectorised over chirps: predictor xhat[n] = sum a(j) x[n-j]
a = zeros(p, C); E = r(1, :);
for i = 1:p
    acc = r(i+1, :);
    for j = 1:i-1
        acc = acc - a(j, :) .* r(i-j+1, :);
    end
    k = acc ./ E; k(~isfinite(k)) = 0;
    anew = a;
    anew(i, :) = k;
    for j = 1:i-1
        anew(j, :) = a(j, :) - k .* a(i-j, :);
    end
    a = anew;
    E = E .* (1 - k.^2);
end
a = double(single(a));                       % what the decoder receives
% residual, using only past samples of the same chirp (zeros before the start)
pred = zeros(N, C);
for j = 1:p
    pred(1+j:N, :) = pred(1+j:N, :) + a(j, :) .* x(1:N-j, :);
end
e = x - round(pred);
% decode sample by sample and check
y = zeros(N, C);
for n = 1:N
    s = zeros(1, C);
    for j = 1:min(p, n-1)
        s = s + a(j, :) .* y(n-j, :);
    end
    y(n, :) = e(n, :) + round(s);
end
out.lossless = isequal(y, x);
% Huffman code over the residual values
lo = min(e(:));
cnt = accumarray(e(:) - lo + 1, 1);
len = kr_huffman_lengths(cnt);
out.codeBits = sum(cnt .* len);
out.dictBits = nnz(cnt) * (16 + 5);
out.coefBits = p * 32 * C;
out.inputBits = N * C * 16;
out.CRnoDict = out.inputBits / (out.codeBits + out.coefBits);
out.CR       = out.inputBits / (out.codeBits + out.coefBits + out.dictBits);
out.residualStd = std(e(:));
out.order = p;
end
