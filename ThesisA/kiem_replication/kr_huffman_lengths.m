function len = kr_huffman_lengths(counts)
%KR_HUFFMAN_LENGTHS  Code length of each symbol in an optimal Huffman code
%   built from the symbol counts (two-queue construction). Symbols with zero
%   count get length 0. Used where Kiem's text says the dictionary is built
%   from the data ("ideal" DRHE [2.7.3], LPC-Huffman [2.7.4]).
counts = counts(:);
len = zeros(size(counts));
used = find(counts > 0);
n = numel(used);
if n == 0, return; end
if n == 1, len(used) = 1; return; end
[w, ord] = sort(counts(used));
leaf = used(ord);
parent = zeros(2*n - 1, 1);
weight = [w; zeros(n - 1, 1)];
i1 = 1; i2 = n + 1; next = n + 1;             % queue heads and next free node
for k = 1:n-1
    pick = zeros(1, 2);
    for j = 1:2
        if i1 <= n && (i2 >= next || weight(i1) <= weight(i2))
            pick(j) = i1; i1 = i1 + 1;
        else
            pick(j) = i2; i2 = i2 + 1;
        end
    end
    weight(next) = weight(pick(1)) + weight(pick(2));
    parent(pick) = next;
    next = next + 1;
end
depth = zeros(2*n - 1, 1);
for node = 2*n-2:-1:1                         % parents always have larger index
    depth(node) = depth(parent(node)) + 1;
end
len(leaf) = depth(1:n);
end
