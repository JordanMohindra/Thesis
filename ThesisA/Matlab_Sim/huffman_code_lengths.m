function lengths = huffman_code_lengths(counts, pseudoCount)
% HUFFMAN_CODE_LENGTHS Optimal (Huffman) code lengths from symbol counts.
%   lengths = huffman_code_lengths(counts, pseudoCount)
%   counts      - 1x16 histogram of S4 values (S4 = 0..15)
%   pseudoCount - added to every count so every S4 keeps a codeword
%                 (default 1, as used for the re-derived tables)
%
%   Standard Huffman construction: repeatedly merge the two least frequent
%   nodes; every merge adds one bit to all symbols underneath. Ties are
%   broken by lowest index, so lengths can differ from another tool's in
%   tied cases while giving the same total cost on the training data.
    if nargin < 2, pseudoCount = 1; end
    w = double(counts(:).') + pseudoCount;
    n = numel(w);
    lengths = zeros(1, n);
    groups  = num2cell(1:n);        % symbols under each live node
    weights = w;
    while numel(weights) > 1
        [~, order] = sort(weights);
        a = order(1); b = order(2);
        merged = [groups{a}, groups{b}];
        lengths(merged) = lengths(merged) + 1;
        keep = true(1, numel(weights)); keep([a b]) = false;
        groups  = [groups(keep), {merged}];
        weights = [weights(keep), weights(a) + weights(b)];
    end
end
